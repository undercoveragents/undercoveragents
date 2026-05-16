# frozen_string_literal: true

module ChannelPlugin
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

        raise ArgumentError, "Channel type '#{registry_key}' is already registered"
      end

      @type_map[registry_key] = klass_name
      @label_map[registry_key] = metadata.fetch(:label)
      @icon_map[registry_key] = metadata.fetch(:icon)
      @description_map[registry_key] = metadata.fetch(:description, "")
      @source_map[registry_key] = metadata.fetch(:source, :plugin).to_sym
    end

    def register_core_types!
      [Channels::Client, Channels::Api].each do |klass|
        register(
          klass.key,
          klass.name,
          label: klass.label,
          icon: klass.icon,
          description: klass.description,
          source: :app,
        )
      end
    end

    def reset!
      @type_map = {}
      @label_map = {}
      @icon_map = {}
      @description_map = {}
      @source_map = {}
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
      ensure_registered_types!

      @label_map[key.to_s]
    end

    def icon_for(key)
      ensure_registered_types!

      @icon_map[key.to_s]
    end

    def app_owned?(key)
      @source_map[key.to_s] == :app
    end

    private

    def ensure_registered_types!
      return unless plugin_system_available?

      registry = UndercoverAgents::PluginSystem.registry
      return if skip_registration?(registry)
      return unless needs_registration?(registry)

      UndercoverAgents::PluginSystem.register_channel_types!
    rescue StandardError
      nil
    end

    def plugin_system_available?
      defined?(UndercoverAgents::PluginSystem)
    end

    def skip_registration?(registry)
      registry.respond_to?(:empty?) && registry.empty? && @type_map.empty?
    end

    def needs_registration?(registry)
      @type_map.empty? || missing_registered_types?(registry)
    end

    def missing_registered_types?(registry)
      expected_class_names = [Channels::Client.name, Channels::Api.name]
      expected_class_names.concat(
        registry.all.to_a.flat_map do |definition|
          definition.channel_entry_points.map do |entry|
            UndercoverAgents::PluginSystem.send(:normalize_channel_class_name, entry.fetch(:class_name))
          end
        end,
      )

      expected_class_names.uniq.any? { |class_name| !@type_map.value?(class_name) }
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

    def target_kinds(value = nil)
      return @target_kinds || ["agent"] if value.nil?

      @target_kinds = Array(value).map(&:to_s)
    end

    def requires_connector_type(value = nil)
      return @requires_connector_type if value.nil?

      @requires_connector_type = value.to_s
    end

    def delivery_adapter_class(value = nil)
      return @delivery_adapter_class if value.nil?

      @delivery_adapter_class = value
    end

    def permitted_params(raw)
      raw.permit
    end

    def build_from_params(params)
      new(permitted_params(params))
    end
  end

  attr_accessor :_channel_record

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
end
