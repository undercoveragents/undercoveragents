# frozen_string_literal: true

module ToolDesigner
  class FieldMetadata
    FIELD_NOTES = {
      "tool_widget_icon" => "Must be a valid Font Awesome class pair.",
      "tool_widget_running_messages" => "Array of short status lines shown while the tool runs.",
      "tool_widget_complete_messages" => "Array of short status lines shown after the tool completes.",
      "tool_widget_running_mode" => "Controls whether running messages rotate or stay fixed.",
      "tool_widget_running_interval_ms" => "Rotation interval in milliseconds for running messages.",
      "tool_compaction_policy" => "Controls stale tool-result compaction for long chats.",
    }.freeze
    TYPE_LABELS = {
      ActiveModel::Type::Boolean => "boolean",
      ActiveModel::Type::DateTime => "datetime",
      ActiveModel::Type::Float => "float",
      ActiveModel::Type::Integer => "integer",
      ActiveModel::Type::String => "string",
    }.freeze

    def initialize(toolable_class, sample_configurator)
      @toolable_class = toolable_class
      @sample_configurator = sample_configurator
    end

    def line(field_name)
      "- `#{field_name}` (#{field_type(field_name)}, #{field_requirement(field_name)})#{field_note(field_name)}"
    end

    private

    def field_type(field_name)
      sample = sample_value(field_name)
      return "array" if sample.is_a?(Array)
      return "object" if sample.is_a?(Hash)
      return "value" unless @toolable_class.respond_to?(:attribute_types)

      type_label_for(@toolable_class.attribute_types[field_name.to_s])
    end

    def sample_value(field_name)
      return unless @sample_configurator.respond_to?(field_name)

      @sample_configurator.public_send(field_name)
    end

    def field_requirement(field_name)
      validators = validators_for(field_name).select { |validator| validator.kind == :presence }
      return "optional" if validators.empty?
      return "required" if validators.any? { |validator| unconditional_validator?(validator) }

      "conditionally required"
    end

    def field_note(field_name)
      field_hint = @toolable_class.tool_designer_field_hints[field_name.to_s]
      note = FIELD_NOTES[field_name.to_s]
      parts = []
      parts << note if note.present?
      parts.concat(Array(render_field_hint(field_hint)))
      parts.concat(field_constraints(field_name))
      parts << default_value_note(field_name)

      parts.compact_blank!
      parts.any? ? " — #{parts.join(" ")}" : ""
    end

    def validators_for(field_name)
      return [] unless @toolable_class.respond_to?(:validators_on)

      @toolable_class.validators_on(field_name.to_sym)
    end

    def unconditional_validator?(validator)
      !validator.options.key?(:if) && !validator.options.key?(:unless)
    end

    def field_constraints(field_name)
      validators_for(field_name).flat_map do |validator|
        case validator.kind
        when :inclusion
          inclusion_constraint(validator)
        when :numericality
          numericality_constraint(validator)
        when :length
          length_constraint(validator)
        end
      end.compact
    end

    def inclusion_constraint(validator)
      values = validator_values(validator.options[:in])
      return if values.blank?

      "Allowed values: #{values.map { |value| "`#{value}`" }.join(", ")}."
    end

    def numericality_constraint(validator)
      parts = numericality_parts(validator.options)
      return if parts.empty?

      "Numeric constraint: #{parts.join(", ")}."
    end

    def numericality_parts(options)
      [].tap do |parts|
        parts << "integer" if options[:only_integer]
        parts << ">= #{options[:greater_than_or_equal_to]}" if options.key?(:greater_than_or_equal_to)
        parts << "> #{options[:greater_than]}" if options.key?(:greater_than)
        parts << "<= #{options[:less_than_or_equal_to]}" if options.key?(:less_than_or_equal_to)
        parts << "< #{options[:less_than]}" if options.key?(:less_than)
      end
    end

    def length_constraint(validator)
      maximum = validator.options[:maximum]
      return if maximum.blank?

      "Maximum length: #{maximum}."
    end

    def validator_values(raw_values)
      values = raw_values.respond_to?(:call) ? raw_values.call(@sample_configurator) : raw_values
      return unless values.respond_to?(:to_a)

      values.to_a
    rescue StandardError
      nil
    end

    def default_value_note(field_name)
      value = sample_value(field_name)
      return if value.blank?

      "Default: `#{format_default_value(value)}`."
    end

    def format_default_value(value)
      return JSON.generate(value) if value.is_a?(Array) || value.is_a?(Hash)

      value
    end

    def render_field_hint(field_hint)
      return if field_hint.blank?
      return field_hint if field_hint.is_a?(String)
      return unless field_hint.respond_to?(:to_h)

      normalized_hint = field_hint.to_h.stringify_keys
      rendered_parts = []

      if normalized_hint["resource_kind"].present?
        rendered_parts <<
          "Use list_resources(kind: \"#{normalized_hint.fetch("resource_kind")}\") to resolve exact IDs."
      end

      rendered_parts << normalized_hint["note"] if normalized_hint["note"].present?
      rendered_parts
    end

    def type_label_for(type)
      TYPE_LABELS.each do |klass, label|
        return label if type.is_a?(klass)
      end

      "value"
    end
  end
end
