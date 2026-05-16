# frozen_string_literal: true

module Tools
  class AdminManager
    ActionResult = Data.define(:success?, :message)

    TOOL_ATTRIBUTE_KEYS = ["name", "description", "enabled"].freeze
    RUNTIME_ATTRIBUTE_KEYS = ["tool_type", "toolable_attributes", *TOOL_ATTRIBUTE_KEYS].freeze
    WIDGET_ATTRIBUTE_ALIASES = {
      "icon" => "tool_widget_icon",
      "running_messages" => "tool_widget_running_messages",
      "complete_messages" => "tool_widget_complete_messages",
      "completion_messages" => "tool_widget_complete_messages",
    }.freeze

    def build(operation:, tool_type:, tool_attributes:, toolable_attributes: nil)
      parsed_tool_attributes, parsed_toolable_attributes = parse_updates(tool_attributes, toolable_attributes)
      validate_tool_attributes!(parsed_tool_attributes)

      toolable_class = resolve_toolable_class(tool_type)
      validate_toolable_attributes!(toolable_class, parsed_toolable_attributes)

      tool = Tool.new(parsed_tool_attributes.merge("tool_type" => tool_type.to_s, "operation" => operation))
      tool.configurator = toolable_class.new(parsed_toolable_attributes.symbolize_keys)
      tool
    end

    def build_from_params(operation:, tool_type:, tool_attributes:, params:)
      parsed_tool_attributes = parse_hash(tool_attributes)
      validate_tool_attributes!(parsed_tool_attributes)

      toolable_class = resolve_toolable_class(tool_type)
      tool = Tool.new(parsed_tool_attributes.merge("tool_type" => tool_type.to_s, "operation" => operation))
      tool.configurator = toolable_class.build_from_params(params)
      tool
    end

    def update!(tool:, tool_attributes: nil, toolable_attributes: nil)
      parsed_tool_attributes, parsed_toolable_attributes = parse_updates(tool_attributes, toolable_attributes)
      raise ArgumentError, "Provide tool_attributes and/or toolable_attributes." if
        parsed_tool_attributes.blank? && parsed_toolable_attributes.blank?

      validate_tool_attributes!(parsed_tool_attributes)
      validate_toolable_attributes!(tool.toolable.class, parsed_toolable_attributes)

      persist_updates(tool, parsed_tool_attributes, parsed_toolable_attributes)

      tool
    end

    def update_from_params!(tool:, tool_attributes:, params:)
      parsed_tool_attributes = parse_hash(tool_attributes)
      parsed_toolable_attributes = tool.toolable.class.permitted_params(params)

      validate_tool_attributes!(parsed_tool_attributes)
      persist_updates(tool, parsed_tool_attributes, parsed_toolable_attributes)

      tool
    end

    def destroy!(tool:)
      tool.destroy!
    end

    def perform_action!(tool:, action:, selected_items: nil)
      normalized_action = normalized_action_key(action)
      validate_action_supported!(tool.toolable.class, normalized_action)

      result = tool.toolable.perform_tool_designer_action!(
        normalized_action,
        { "selected_items" => selected_items },
      )
      ActionResult.new(success?: result.success?, message: result.message)
    end

    def parse_hash(value)
      case value
      when nil
        {}
      when ActionController::Parameters
        value.to_unsafe_h.stringify_keys
      when Hash
        value.stringify_keys
      when String
        parse_string_hash(value)
      else
        raise ArgumentError, "Expected a hash or JSON object string."
      end
    end

    def parse_string_hash(value)
      stripped = value.strip
      return {} if stripped.empty?

      parsed = JSON.parse(stripped)
      raise ArgumentError, "Expected a JSON object." unless parsed.is_a?(Hash)

      parsed.stringify_keys
    end

    def parse_updates(tool_attributes, toolable_attributes)
      [parse_hash(tool_attributes), normalize_toolable_attributes(parse_hash(toolable_attributes))]
    end

    def normalize_toolable_attributes(toolable_attributes)
      normalized = toolable_attributes.stringify_keys

      WIDGET_ATTRIBUTE_ALIASES.each do |source_key, target_key|
        next unless normalized.key?(source_key)

        if normalized.key?(target_key)
          normalized.delete(source_key)
          next
        end

        normalized[target_key] = normalized.delete(source_key)
      end

      normalized
    end

    def invalid_tool_attributes(tool_attributes)
      tool_attributes.keys - TOOL_ATTRIBUTE_KEYS
    end

    private

    def normalized_action_key(action)
      normalized = action.to_s.strip
      return normalized if normalized.present?

      raise ArgumentError, "Provide an action."
    end

    def resolve_toolable_class(tool_type)
      toolable_class = ToolPlugin.resolve(tool_type)
      return toolable_class if toolable_class

      raise ArgumentError, "Unknown tool type '#{tool_type}'."
    end

    def validate_tool_attributes!(tool_attributes)
      unknown_tool_attributes = invalid_tool_attributes(tool_attributes)
      return if unknown_tool_attributes.empty?

      raise ArgumentError, "Unknown tool attributes: #{unknown_tool_attributes.join(", ")}"
    end

    def validate_toolable_attributes!(toolable_class, toolable_attributes)
      return if toolable_attributes.blank?

      allowed_keys = toolable_class.tool_designer_editable_attributes.map(&:to_s)
      unknown_toolable_attributes = toolable_attributes.keys - allowed_keys
      return if unknown_toolable_attributes.empty?

      raise ArgumentError,
            "Unknown #{toolable_class.type_label} configuration keys: #{unknown_toolable_attributes.join(", ")}"
    end

    def persist_updates(tool, tool_attributes, toolable_attributes)
      Tool.transaction do
        tool.update!(tool_attributes) if tool_attributes.present?
        tool.toolable.update!(toolable_attributes) if toolable_attributes.present?
      end
    end

    def validate_action_supported!(toolable_class, action)
      action_key = action.to_s
      supported_action_keys = toolable_class.tool_designer_actions.map { |entry| entry.fetch("key") }
      return if supported_action_keys.include?(action_key)

      message = "Action '#{action_key}' is not supported for #{toolable_class.type_label}."
      message = "#{message} Use #{supported_action_keys.join(", ")}." if supported_action_keys.any?
      raise ArgumentError, message
    end
  end
end
