# frozen_string_literal: true

module AgentDesigner
  class ManageAgentActionTool < RubyLLM::Tool
    include AgentLookup
    include CurrentPageRefreshable
    include PolicyAuthorizable

    ACTIONS = {
      "restore" => :restore,
      "restore_defaults" => :restore_defaults,
    }.freeze

    description "Run agent admin actions that are not covered by generic CRUD, such as restoring built-ins."

    param :action,
          desc: "Agent action to run. Supported values: 'restore' or 'restore_defaults'."

    param :agent_id,
          desc: "Optional numeric ID or slug. Omit to act on the current agent from page context.",
          required: false

    def initialize(runtime_context:, current_agent: nil)
      super()
      @runtime_context = runtime_context
      @current_agent = current_agent
    end

    def name = "manage_agent_action"

    def execute(action:, agent_id: nil)
      normalized_action = ACTIONS[action.to_s]
      return "Error: Unknown action '#{action}'. Use restore or restore_defaults." unless normalized_action

      case normalized_action
      when :restore
        restore_agent(agent_id)
      when :restore_defaults
        restore_defaults
      end
    rescue ActiveRecord::RecordNotFound, ArgumentError, Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error managing agent action: #{e.message}"
    end

    private

    def restore_agent(agent_id)
      agent = resolve_agent(agent_id)
      return missing_agent_message if agent.nil?

      authorize_policy!(agent, :restore?, user: @runtime_context.user)
      raise ArgumentError, "Agent '#{agent.name}' is not a built-in agent." unless agent.builtin?

      BuiltinAgents::Synchronizer.restore!(agent.builtin_key, tenant:)
      restored_agent = Agent.find_builtin_by_key(agent.builtin_key, tenant:)
      refreshed = broadcast_current_page_refresh?

      [
        "Agent action completed.",
        "- Agent: #{restored_agent.name} (`#{restored_agent.id}`)",
        "- Action: `restore`",
        "- Result: Built-in agent restored to the shipped defaults.",
        ("Current page refresh started to show the saved agent." if refreshed),
      ].compact.join("\n")
    end

    def restore_defaults
      authorize_policy!(Agent, :restore_defaults?, user: @runtime_context.user)

      result = BuiltinAgents::Synchronizer.restore_all!(tenant:)
      count = result.restored_keys.size + result.created_keys.size
      refreshed = broadcast_current_page_refresh?

      [
        "Agent action completed.",
        "- Action: `restore_defaults`",
        "- Result: Restored #{count} built-in #{"agent".pluralize(count)}.",
        ("Current page refresh started to show the saved agents." if refreshed),
      ].compact.join("\n")
    end

    def tenant
      @runtime_context&.tenant || @current_agent&.operation&.tenant || Current.tenant || Tenant.default_tenant
    end
  end
end
