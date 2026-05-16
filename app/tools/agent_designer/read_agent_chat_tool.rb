# frozen_string_literal: true

module AgentDesigner
  class ReadAgentChatTool < RubyLLM::Tool
    include AgentLookup
    include PolicyAuthorizable

    description "Inspect recent chats or one specific chat for the current agent, " \
                "including inspector-style message details."

    param :agent_id,
          desc: "Optional numeric ID or slug. Omit to inspect the current agent from page context.",
          required: false
    param :chat_id,
          desc: "Optional chat ID to inspect. When omitted, use selector='latest' or selector='recent'.",
          required: false
    param :selector,
          desc: "Chat selection mode when chat_id is omitted: 'latest' (default) or 'recent'.",
          required: false
    param :limit,
          desc: "Optional max number of chats when selector='recent'.",
          required: false
    param :detail,
          desc: "Response detail for one chat: 'summary' (default) or 'full'.",
          required: false
    param :message_limit,
          desc: "Optional number of most recent messages to include for a single chat.",
          required: false

    def initialize(runtime_context:, current_agent: nil)
      super()
      @runtime_context = runtime_context
      @current_agent = current_agent
    end

    def name = "read_agent_chat"

    def execute(agent_id: nil, chat_id: nil, selector: nil, **options)
      agent = authorized_agent(agent_id)
      return missing_agent_message if agent.nil?

      selected_chat_response(agent, chat_id:, selector:, options:)
    rescue ActiveRecord::RecordNotFound, ArgumentError, Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error reading agent chats: #{e.message}"
    end

    private

    def authorized_agent(agent_id)
      agent = resolve_agent(agent_id)
      return if agent.nil?

      authorize_policy!(agent, :show?, user: @runtime_context.user)
      agent
    end

    def selected_chat_response(agent, chat_id:, selector:, options:)
      chat_options = {
        detail: options[:detail],
        limit: options[:limit],
        message_limit: options[:message_limit],
      }

      if chat_id.present?
        return read_specific_chat(
          agent,
          chat_id,
          detail: chat_options[:detail],
          message_limit: chat_options[:message_limit],
        )
      end

      read_selected_chats(agent, selector:, **chat_options)
    end

    def read_specific_chat(agent, chat_id, detail:, message_limit:)
      chat = agent_chat_scope(agent).find_by(id: chat_id)
      return "No chat with ID '#{chat_id}' was found for '#{agent.name}'." unless chat

      formatter(agent).format_chat(chat, detail:, message_limit:)
    end

    def read_selected_chats(agent, selector:, limit:, detail:, message_limit:)
      chats = agent_chat_scope(agent)

      case formatter(agent).normalized_selector(selector)
      when "latest"
        latest_chat = chats.first
        return "No chats found for '#{agent.name}'." unless latest_chat

        formatter(agent).format_chat(latest_chat, detail:, message_limit:)
      when "recent"
        formatter(agent).format_recent_chats(chats, limit:)
      end
    end

    def agent_chat_scope(agent)
      agent.chats.includes(:agent, :model, :parent_chat, :user).recent
    end

    def formatter(agent)
      AgentDesigner::ChatDebugFormatter.new(agent:)
    end
  end
end
