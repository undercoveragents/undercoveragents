# frozen_string_literal: true

# Provides the capability plugin protocol for capability configurator models.
#
# Each plugin capability model includes this concern and implements:
#
# Class methods (metadata & params):
#   - key              → "chat_title_generator"
#   - label            → "Chat Title Generator"
#   - icon             → "fa-solid fa-heading"
#   - description      → human-readable capability description
#   - permitted_params → strong params extraction
#   - build_from_params → factory for new instances
#
# Instance methods (behavior):
#   - summary          → one-line human-readable description
#   - form_partial_path → absolute path to directory containing _form.html.haml
#   - form_locals      → optional hash of plugin-specific locals for capability form rendering
module CapabilityPlugin
  extend ActiveSupport::Concern

  @type_map = {}
  @label_map = {}
  @icon_map = {}
  @description_map = {}

  class << self
    def register(key, class_name, label:, icon:, description: "")
      registry_key = key.to_s
      klass_name = class_name.to_s

      if @type_map.key?(registry_key)
        existing_class = @type_map[registry_key]
        return if existing_class == klass_name

        raise ArgumentError, "Capability type '#{registry_key}' is already registered"
      end

      @type_map[registry_key] = klass_name
      @label_map[registry_key] = label
      @icon_map[registry_key] = icon
      @description_map[registry_key] = description
    end

    def reset!
      @type_map = {}
      @label_map = {}
      @icon_map = {}
      @description_map = {}
    end

    def type_map
      ensure_registered_types!

      @type_map.dup
    end

    def resolve(key)
      ensure_registered_types!

      class_name = @type_map[key.to_s]
      class_name&.constantize
    end

    def type_keys
      ensure_registered_types!

      @type_map.keys
    end

    def all_types
      ensure_registered_types!

      registry = UndercoverAgents::PluginSystem.registry

      @type_map.keys.filter_map do |key|
        next unless registry.enabled?(key)

        klass = @type_map[key].constantize
        {
          key:,
          label: @label_map[key],
          icon: @icon_map[key],
          description: klass.respond_to?(:description) ? klass.description : @description_map[key],
        }
      end
    end

    def label_for(key)
      ensure_registered_types!

      @label_map[key.to_s]
    end

    def icon_for(key)
      ensure_registered_types!

      @icon_map[key.to_s]
    end

    private

    def ensure_registered_types!
      return unless @type_map.empty?
      return unless defined?(UndercoverAgents::PluginSystem)

      registry = UndercoverAgents::PluginSystem.registry
      return if registry.empty?

      UndercoverAgents::PluginSystem.register_capability_types!
    rescue StandardError
      nil
    end
  end

  attr_accessor :_agent_record

  module ClassMethods
    def key(value = nil)
      return @key if value.nil?

      @key = value.to_s
    end

    def label(value = nil)
      return @label if value.nil?

      @label = value
    end

    def icon(value = nil)
      return @icon if value.nil?

      @icon = value
    end

    def description(value = nil)
      return @description || "" if value.nil?

      @description = value
    end

    def permitted_params(raw)
      raw.permit
    end

    def build_from_params(params)
      new(permitted_params(params))
    end

    def event_handler_class
      nil
    end

    def agent_designer_fields
      defaults = new

      attribute_types.map do |name, type|
        {
          name:,
          type: type.type.to_s,
          default: defaults.public_send(name),
        }
      end
    end

    def agent_designer_notes
      []
    end

    def scoped
      Agent.where(
        "configuration->'capabilities' ? :key " \
        "AND (configuration->'capabilities'->:key->>'enabled')::boolean = true",
        key:,
      )
    end

    delegate :find, :find_by, :where, :count, :last, :first,
             :exists?, :pluck, :ids, :connection, to: :scoped
  end

  delegate :label, to: :class

  def summary
    self.class.label
  end

  def agent
    _agent_record
  end

  def capability_tenant
    agent&.tenant || Current.tenant
  end

  def connector_scope
    capability_tenant ? capability_tenant.connectors : Connector.all
  end

  def find_connector(connector_id)
    ConnectorLookup.find(connector_id, tenant: capability_tenant)
  end

  def form_partial_path
    model_file, = Object.const_source_location(self.class.name)
    model_file.sub(%r{/app/models/.*$}, "/app/views")
  end

  def form_locals
    {}
  end
end
