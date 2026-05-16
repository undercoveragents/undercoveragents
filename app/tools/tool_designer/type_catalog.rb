# frozen_string_literal: true

module ToolDesigner
  class TypeCatalog
    COMMON_FIELDS = {
      "name" => "Human-readable tool name.",
      "description" => "Optional admin-facing description shown in the UI and to agents.",
      "enabled" => "Whether the tool can be assigned and used at runtime.",
    }.freeze

    def initialize(tool_type)
      @tool_type = tool_type.to_s
      @toolable_class = ToolPlugin.resolve(@tool_type)
      @sample_configurator = @toolable_class&.new
    end

    def render
      return unknown_tool_type_message unless @toolable_class

      [
        summary_section,
        common_fields_section,
        editable_fields_section,
        actions_section,
        notes_section,
      ].compact.join("\n\n")
    end

    def editable_field_names
      return [] unless @toolable_class

      @toolable_class.tool_designer_editable_attributes.map(&:to_s)
    end

    def action_keys
      return [] unless @toolable_class

      @toolable_class.tool_designer_actions.map { |entry| entry.fetch("key") }
    end

    private

    def summary_section
      [
        "## Tool Type",
        "- Key: `#{@tool_type}`",
        "- Label: #{@toolable_class.type_label}",
        "- Description: #{tool_type_description}",
      ].join("\n")
    end

    def common_fields_section
      lines = ["## Common Tool Fields"]
      COMMON_FIELDS.each do |field_name, note|
        lines << "- `#{field_name}` — #{note}"
      end
      lines.join("\n")
    end

    def editable_fields_section
      field_names = editable_field_names
      return "## Type-Specific Editable Fields\n- None" if field_names.empty?

      lines = ["## Type-Specific Editable Fields"]
      field_names.each do |field_name|
        lines << field_metadata.line(field_name)
      end
      lines.join("\n")
    end

    def actions_section
      actions = @toolable_class.tool_designer_actions
      return "## Supported Actions\n- None" if actions.empty?

      lines = ["## Supported Actions"]
      actions.each do |action|
        lines << "- `#{action.fetch("key")}` — #{action.fetch("description")}#{action_arguments(action)}"
      end
      lines.join("\n")
    end

    def notes_section
      notes = @toolable_class.tool_designer_notes
      return if notes.empty?

      ["## Notes", *notes.map { |note| "- #{note}" }].join("\n")
    end

    def action_arguments(action)
      arguments = Array(action["arguments"])
      return "" if arguments.empty?

      rendered = arguments.map do |argument|
        normalized_argument = argument.to_h.stringify_keys
        requirement = normalized_argument["required"] ? "required" : "optional"
        description = normalized_argument["description"].presence
        suffix = description ? ": #{description}" : ""
        name = normalized_argument.fetch("name")
        type = normalized_argument.fetch("type", "value")
        "`#{name}` (#{type}, #{requirement})#{suffix}"
      end
      " Arguments: #{rendered.join(", ")}."
    end

    def unknown_tool_type_message
      "Unknown tool type '#{@tool_type}'. Use list_resources(kind: \"tool_types\")."
    end

    def tool_type_description
      ToolPlugin.all_types.find { |type| type.fetch(:key) == @tool_type }
                          &.fetch(:description)
                .presence || "None"
    end

    def field_metadata
      @field_metadata ||= ToolDesigner::FieldMetadata.new(@toolable_class, @sample_configurator)
    end
  end
end
