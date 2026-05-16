# frozen_string_literal: true

module Capabilities
  class TitleGenerationService
    HANDLED_EVENTS = [:chat_response_completed].freeze

    def initialize(config)
      @config = config
    end

    def handle(event, chat:, **)
      return unless HANDLED_EVENTS.include?(event)

      handle_chat_response_completed(chat)
    end

    private

    def handle_chat_response_completed(chat)
      @chat = chat
      @agent = chat.agent
      return unless should_generate?

      title = generate_title
      return if title.blank?

      @chat.update!(title: title.truncate(@config.max_length))
      broadcast_chat_title
    rescue StandardError => e
      Rails.logger.error "[TitleGenerationService] Error generating title for chat #{@chat.id}: #{e.message}"
    end

    def should_generate?
      return false unless @agent
      return false unless @config

      user_turn_count = @chat.messages.where(role: :user).count
      user_turn_count.between?(1, @config.max_turns)
    end

    def generate_title
      model_id = @config.resolve_model_id(@agent)
      temperature = @config.resolve_temperature(@agent)
      connector = @config.resolve_connector(@agent)
      context = connector&.build_context

      title_chat = BuiltinAgents::Runner.build_chat!(
        builtin_key: "chat_title_generator",
        model_id:,
        temperature:,
        llm_context: context,
        title: "Title Generation",
        parent_chat: @chat,
        execution_context: :system,
        input_values: { max_length: @config.max_length },
      )

      conversation_summary = build_conversation_summary
      response = title_chat.ask(conversation_summary)
      clean_title(response.content)
    end

    def build_conversation_summary
      messages = @chat.messages
                      .where(role: [:user, :assistant])
                      .order(:created_at)
                      .limit(@config.max_turns * 2)

      messages.map { |message| "#{message.role}: #{message.content&.truncate(500)}" }.join("\n")
    end

    def clean_title(content)
      return nil if content.blank?

      content.strip.delete_prefix('"').delete_suffix('"')
    end

    def broadcast_chat_title
      @chat.broadcast_title_update
    end
  end
end
