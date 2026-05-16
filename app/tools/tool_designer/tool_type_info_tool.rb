# frozen_string_literal: true

module ToolDesigner
  class ToolTypeInfoTool < RubyLLM::Tool
    description "Show the editable configuration fields, plugin notes, and supported actions for a tool type."

    param :tool_type,
          desc: "Optional tool type key. Omit to use the current tool page context.",
          required: false

    def initialize(current_tool: nil)
      super()
      @current_tool = current_tool
    end

    def name = "get_tool_type_info"

    def execute(tool_type: nil)
      resolved_type = tool_type.to_s.presence || @current_tool&.tool_type
      return "Provide tool_type or open a tool page first." if resolved_type.blank?

      ToolDesigner::TypeCatalog.new(resolved_type).render
    rescue StandardError => e
      "Error reading tool type info: #{e.message}"
    end
  end
end
