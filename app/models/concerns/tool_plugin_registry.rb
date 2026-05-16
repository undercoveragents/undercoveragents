# frozen_string_literal: true

module ToolPluginRegistry
  def register(key, class_name, label:, icon:, description: "")
    registry_key = key.to_s
    klass_name = class_name.to_s

    # :nocov:
    if @type_map.key?(registry_key)
      existing_class = @type_map[registry_key]
      return if existing_class == klass_name

      raise ArgumentError, "Tool type '#{registry_key}' is already registered"
    end
    # :nocov:

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
    @type_map.dup
  end

  def resolve(type_key)
    ensure_registered_types!

    class_name = @type_map[type_key.to_s]
    class_name&.constantize
  end

  def sanitize_runtime_fragment(value)
    value.to_s
         .unicode_normalize(:nfkd)
         .encode("ASCII", replace: "")
         .gsub(/[^a-zA-Z0-9_-]/, "_")
         .squeeze("_")
         .gsub(/\A_|_\z/, "")
         .downcase
  end

  def type_keys
    ensure_registered_types!

    @type_map.keys
  end

  def all_types
    ensure_registered_types!

    registry = UndercoverAgents::PluginSystem.registry

    @type_map.keys.filter_map do |key|
      # :nocov:
      next unless registry.enabled?(key)
      # :nocov:

      {
        key:,
        label: @label_map[key],
        icon: @icon_map[key],
        description: @description_map[key],
      }
    end
  end

  def label_for(key)
    @label_map[key.to_s]
  end

  def icon_for(key)
    @icon_map[key.to_s]
  end

  # :nocov:
  def key_for_class_name(class_name)
    ensure_registered_types!

    @type_map.invert[class_name.to_s]
  end

  def filter_type(type_key)
    ensure_registered_types!

    return type_key if @type_map.key?(type_key.to_s)

    key_for_class_name(type_key)
  end
  # :nocov:

  def type_options
    ensure_registered_types!

    @type_map.each_key.map { |key| [label_for(key), key] }
  end

  private

  def ensure_registered_types!
    return unless @type_map.empty?
    return unless defined?(UndercoverAgents::PluginSystem)

    registry = UndercoverAgents::PluginSystem.registry
    return if registry.empty?

    UndercoverAgents::PluginSystem.register_tool_types!
  rescue StandardError
    nil
  end
end
