# frozen_string_literal: true

module Channels
  class AgentInvoker
    class InvalidInvocation < StandardError; end

    Result = Data.define(:chat, :response_content, :sync?)

    def initialize(channel:, channel_target:)
      @channel = channel
      @channel_target = channel_target
      @agent = channel_target.target
    end

    def call(content:, response_mode:)
      raise InvalidInvocation, "Channel target is not an agent" unless @channel_target.target_type == "Agent"
      raise InvalidInvocation, "content can't be blank" if content.blank?

      chat = build_chat

      if response_mode == "sync"
        response = invoke_sync(chat, content)
        Result.new(chat:, response_content: extract_response_content(response), sync?: true)
      else
        chat.enqueue_response!(content:)
        Result.new(chat:, response_content: nil, sync?: false)
      end
    end

    private

    def build_chat
      Chat.create!(
        agent: @agent,
        channel: @channel,
        channel_target: @channel_target,
        execution_context: :channel,
        model: resolved_model!,
        title: Chat::DEFAULT_TITLE,
      )
    end

    def invoke_sync(chat, content)
      chat.configure_for_agent(@agent)
      chat.ask(content)
    end

    def extract_response_content(response)
      return response.content if response.respond_to?(:content)

      response.to_s
    end

    def resolved_model!
      Model.find_by(model_id: @agent.resolved_model_id) ||
        raise(InvalidInvocation, "Agent model is unavailable")
    end
  end
end
