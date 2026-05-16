# frozen_string_literal: true

module MissionNodePluginRegistryMethods
  def register(*args, **kwargs)
    attributes = registration_attributes(args, kwargs)
    registry_key = attributes.fetch(:key).to_s
    klass_name = attributes.fetch(:class_name).to_s

    if @type_map.key?(registry_key)
      existing = @type_map[registry_key]
      return if existing == klass_name

      raise ArgumentError, "Mission node type '#{registry_key}' is already registered"
    end

    @type_map[registry_key] = klass_name
    @metadata_map[registry_key] = registration_metadata(attributes)
  end

  def reset!
    @type_map = {}
    @metadata_map = {}
  end

  def restore_defaults!
    reset!
    register_defaults!
  end

  def register_defaults!
    MissionNodePluginDefaultDefinitions::ALL.each { |definition| register(definition) }
  end

  def type_map
    @type_map.dup
  end

  def resolve(type_key)
    class_name = @type_map[type_key.to_s]
    class_name&.constantize
  end

  def type_keys
    @type_map.keys
  end

  def all_types
    ensure_classes_loaded!
    @type_map.keys.map do |key|
      { key:, **@metadata_map[key] }
    end
  end

  def types_by_category
    all_types.group_by { |type| type[:category] }
  end

  def label_for(key)
    @metadata_map.dig(key.to_s, :label)
  end

  def icon_for(key)
    @metadata_map.dig(key.to_s, :icon)
  end

  def color_for(key)
    @metadata_map.dig(key.to_s, :color)
  end

  def category_for(key)
    @metadata_map.dig(key.to_s, :category)
  end

  def metadata_for(key)
    registry_key = key.to_s
    ensure_class_loaded!(registry_key)
    @metadata_map[registry_key]&.dup
  end

  def ensure_classes_loaded!
    @type_map.each_value(&:safe_constantize)
  end

  def ensure_class_loaded!(key)
    return if @metadata_map.dig(key, :output_ports)

    @type_map[key]&.safe_constantize
  end

  def register_from_class(klass)
    key = klass.node_type.to_s
    @type_map[key] = klass.name
    @metadata_map[key] = {
      label: klass.node_label,
      icon: klass.node_icon,
      color: klass.node_color,
      category: klass.node_category.to_s,
      description: klass.node_description,
      singleton: klass.try(:singleton?) || false,
      output_ports: klass.try(:default_output_ports) || [{ key: "default", label: "Output" }],
      field_contracts: klass.try(:field_contracts)&.map(&:to_h) || [],
    }
  end

  private

  def registration_attributes(args, kwargs)
    return args.first if args.one? && args.first.is_a?(Hash) && kwargs.empty?

    key, class_name = args
    kwargs.merge(key:, class_name:)
  end

  def registration_metadata(attributes)
    {
      label: attributes.fetch(:label),
      icon: attributes.fetch(:icon),
      color: attributes.fetch(:color),
      category: attributes.fetch(:category).to_s,
      description: attributes.fetch(:description, ""),
      singleton: attributes.fetch(:singleton, false),
    }
  end
end
