# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::AgentInvoker do
  let(:tenant) { create(:tenant) }
  let(:operation) { create(:operation, tenant:) }
  let(:agent) { create(:agent, operation:, model_id: "gpt-4.1") }
  let(:channel) { create(:channel, :api, tenant:, operation:) }
  let(:channel_target) { create(:channel_target, channel:, target: agent, default: true) }

  before do
    create(:model, model_id: "gpt-4.1", provider: "openai")
  end

  describe "#call" do
    it "creates async channel chats and enqueues the response", :aggregate_failures do
      chat = create(:chat, :channel_context, agent:, channel:, channel_target:, title: Chat::DEFAULT_TITLE)

      allow(Chat).to receive(:create!).and_return(chat)
      allow(chat).to receive(:enqueue_response!)

      result = described_class.new(channel:, channel_target:).call(content: "Hello", response_mode: "async")

      expect(result.sync?).to be(false)
      expect(result.response_content).to be_nil
      expect(result.chat).to be_persisted
      expect(result.chat.channel).to eq(channel)
      expect(result.chat.channel_target).to eq(channel_target)
      expect(result.chat.execution_context).to eq("channel")
    end

    it "returns synchronous response content from message-like responses" do
      response = instance_double(RubyLLM::Message, content: "Pong")
      chat = create(:chat, :channel_context, agent:, channel:, channel_target:, title: Chat::DEFAULT_TITLE)

      allow(Chat).to receive(:create!).and_return(chat)
      allow(chat).to receive(:configure_for_agent)
      allow(chat).to receive(:ask).with("Ping").and_return(response)

      result = described_class.new(channel:, channel_target:).call(content: "Ping", response_mode: "sync")

      expect(result.sync?).to be(true)
      expect(result.response_content).to eq("Pong")
    end

    it "falls back to stringifying non-message sync responses" do
      chat = instance_double(Chat)
      invoker = described_class.new(channel:, channel_target:)

      allow(invoker).to receive(:build_chat).and_return(chat)
      allow(chat).to receive(:configure_for_agent)
      allow(chat).to receive(:ask).with("Ping").and_return(:pong)

      result = invoker.call(content: "Ping", response_mode: "sync")

      expect(result.response_content).to eq("pong")
    end

    it "rejects non-agent targets" do
      mission = create(:mission, operation:)
      mission_target = create(:channel_target, :mission, channel:, target: mission)

      expect do
        described_class.new(channel:, channel_target: mission_target).call(content: "Hello", response_mode: "async")
      end.to raise_error(described_class::InvalidInvocation, "Channel target is not an agent")
    end

    it "rejects blank content" do
      expect do
        described_class.new(channel:, channel_target:).call(content: "", response_mode: "async")
      end.to raise_error(described_class::InvalidInvocation, "content can't be blank")
    end

    it "raises when the agent model cannot be resolved" do
      agent.update!(model_id: "missing-model")

      expect do
        described_class.new(channel:, channel_target:).call(content: "Hello", response_mode: "async")
      end.to raise_error(described_class::InvalidInvocation, "Agent model is unavailable")
    end
  end
end
