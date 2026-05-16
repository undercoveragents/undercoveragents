# frozen_string_literal: true

module ToolDesigner
  class ManageToolActionTool < RubyLLM::Tool
    include ToolLookup
    include PolicyAuthorizable

    description "Run an existing tool-specific admin action such as discovery or visibility updates."

    param :action,
          desc: "Tool action to run. Use a key exposed for the tool type, such as 'discover' or 'set_visibility'."

    param :tool_id,
          desc: "Optional numeric ID or slug. Omit to act on the current tool from page context.",
          required: false

    param :selected_items,
          desc: "Optional array of discovered item names for the set_visibility action.",
          type: :array,
          required: false

    def initialize(runtime_context:, current_tool: nil)
      super()
      @runtime_context = runtime_context
      @current_tool = current_tool
    end

    def name = "manage_tool_action"

    def execute(action:, tool_id: nil, selected_items: nil)
      tool = resolve_tool(tool_id)
      return missing_tool_message if tool.nil?

      authorize_tool_action!(tool, action)

      result = ::Tools::AdminManager.new.perform_action!(tool:, action:, selected_items:)
      return "Error: #{result.message}" unless result.success?

      refreshed = tool_refreshed?(tool)

      [
        "Tool action completed.",
        "- Tool: #{tool.name} (`#{tool.id}`)",
        "- Action: `#{action}`",
        "- Result: #{result.message}",
        ("Current page refresh started to show the saved tool." if refreshed),
      ].compact.join("\n")
    rescue ActiveRecord::RecordNotFound, ArgumentError, Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error managing tool action: #{e.message}"
    end

    private

    def tool_refreshed?(tool)
      RuntimeRecords::Refresh.broadcast!(
        context: @runtime_context,
        resource: "tool",
        record: tool,
      ) == :broadcasted
    end

    def authorize_tool_action!(tool, action)
      query = tool.toolable.class.tool_designer_action_policy_query(action)
      return unless query

      authorize_policy!(tool, query, user: @runtime_context.user)
    end
  end
end
