# frozen_string_literal: true

require "ruby_llm/providers/deepseek/chat"

module UndercoverAgents
  module RubyLlmDeepSeekReasoningContentPatch
    def format_thinking(message)
      return {} unless message.role == :assistant

      thinking = message.thinking
      text = thinking&.text.to_s
      payload = { reasoning_content: text }
      payload[:reasoning] = text unless text.empty?
      payload[:reasoning_signature] = thinking.signature if thinking&.signature
      payload
    end
  end
end

RubyLLM::Providers::DeepSeek::Chat.singleton_class.prepend(
  UndercoverAgents::RubyLlmDeepSeekReasoningContentPatch,
)
