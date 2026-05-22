# frozen_string_literal: true

require "rails_helper"

RSpec.describe UndercoverAgents::RubyLlmDeepSeekReasoningContentPatch do
  describe "RubyLLM::Providers::DeepSeek::Chat.format_thinking" do
    it "emits reasoning_content and reasoning when thinking text is present" do
      message = RubyLLM::Message.new(
        role: :assistant,
        content: "Hi",
        thinking: RubyLLM::Thinking.build(text: "pondering", signature: "sig"),
      )

      payload = RubyLLM::Providers::DeepSeek::Chat.format_thinking(message)

      expect(payload).to eq(
        reasoning_content: "pondering",
        reasoning: "pondering",
        reasoning_signature: "sig",
      )
    end

    it "still emits empty reasoning_content when no thinking was captured" do
      message = RubyLLM::Message.new(role: :assistant, content: "short answer")

      payload = RubyLLM::Providers::DeepSeek::Chat.format_thinking(message)

      expect(payload).to eq(reasoning_content: "")
    end

    it "returns an empty hash for non-assistant messages" do
      message = RubyLLM::Message.new(role: :user, content: "hello")

      expect(RubyLLM::Providers::DeepSeek::Chat.format_thinking(message)).to eq({})
    end
  end
end
