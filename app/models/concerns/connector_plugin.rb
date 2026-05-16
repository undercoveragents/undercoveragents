# frozen_string_literal: true

# Provides the connector plugin protocol for connector configurator models.
#
# Each plugin's configurator model includes this concern and implements:
#
# Class methods (metadata & params):
#   - key              → "sql_database"
#   - label            → "SQL Database"
#   - icon             → "fa-solid fa-database"
#   - description      → human-readable connector description for selection cards
#   - sensitive_keys   → array of JSONB keys to encrypt (e.g. [:api_key])
#   - permitted_params → strong params extraction
#   - build_from_params → factory for new instances
#
# Instance methods (behavior):
#   - summary                        → one-line human-readable description
#   - form_partial_path → absolute path to directory containing _form.html.haml
#   - show_partial_path → absolute path to directory containing _show.html.haml
module ConnectorPlugin
  extend ActiveSupport::Concern

  @type_map = {}
  @label_map = {}
  @icon_map = {}
  @description_map = {}
  @source_map = {}

  class << self
    def register(key, class_name, **metadata)
      registry_key = key.to_s
      klass_name = class_name.to_s

      if @type_map.key?(registry_key)
        existing_class = @type_map[registry_key]
        return if existing_class == klass_name

        raise ArgumentError, "Connector type '#{registry_key}' is already registered"
      end

      @type_map[registry_key] = klass_name
      @label_map[registry_key] = metadata.fetch(:label)
      @icon_map[registry_key] = metadata.fetch(:icon)
      @description_map[registry_key] = metadata.fetch(:description, "")
      @source_map[registry_key] = metadata.fetch(:source, :plugin).to_sym
    end

    def register_core_types!
      klass = Connectors::LlmProvider
      register(
        klass.key,
        klass.name,
        label: klass.label,
        icon: klass.icon,
        description: klass.description,
        source: :app,
      )
    end

    def reset!
      @type_map = {}
      @label_map = {}
      @icon_map = {}
      @description_map = {}
      @source_map = {}
    end

    def type_map
      @type_map.dup
    end

    def resolve(key)
      class_name = @type_map[key.to_s]
      class_name&.constantize
    end

    def type_keys
      @type_map.keys
    end

    def all_types
      registry = UndercoverAgents::PluginSystem.registry

      @type_map.keys.filter_map do |key|
        next unless app_owned?(key) || registry.enabled?(key)

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
      @label_map[key.to_s]
    end

    def icon_for(key)
      @icon_map[key.to_s]
    end

    def app_owned?(key)
      @source_map[key.to_s] == :app
    end
  end

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

    def sensitive_keys(value = nil)
      return @sensitive_keys || [] if value.nil?

      @sensitive_keys = Array(value)
    end

    def permitted_params
      []
    end

    def build_from_params(params)
      new(permitted_params(params))
    end

    def list_resources_kind
      nil
    end

    def list_resources_title
      label.to_s.pluralize
    end

    def supports_model_listing?
      false
    end

    def model_provider_key(_connector)
      nil
    end

    # AR delegation allows specs and app code to call plugin configurators like AR models.
    def scoped
      scope = Connector.by_type(key)
      return scope unless Current.tenant

      scope.where(tenant: Current.tenant)
    end

    delegate :find, :find_by, :where, :count, :last, :first,
             :exists?, :pluck, :ids, :connection, to: :scoped
  end

  included do
    before_validation :normalize_blank_credentials
  end

  # Reference to the owning Connector AR record — set by Connector#build_configurator.
  # Useful for validations that need to query the DB (e.g. uniqueness).
  attr_accessor :_connector_record

  delegate :label, to: :class

  def summary
    self.class.label
  end

  def form_partial_path
    model_file, = Object.const_source_location(self.class.name)
    model_file.sub(%r{/app/models/.*$}, "/app/views")
  end

  def show_partial_path
    form_partial_path
  end

  # Returns the name of an extra partial to render on the connector show page,
  # or nil if no extra partial is needed. Override in your configurator.
  def show_extra_partial_name
    nil
  end

  private

  # Normalize blank sensitive fields to nil before validation —
  # mirrors the old STI before_validation callback.
  def normalize_blank_credentials
    self.class.sensitive_keys.each do |field|
      next unless respond_to?(field) && respond_to?("#{field}=")

      value = send(field)
      send("#{field}=", nil) if value.is_a?(String) && value.blank?
    end
  end
end
