# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuites::ChatPromotionService do
  subject(:service_call) { described_class.call(chat:, assistant_message:, user:) }

  let(:user) { create(:user) }
  let(:agent) { create(:agent) }
  let(:chat) { create(:chat, agent:, user:, title: "Support example") }
  let!(:prompt_message) { create(:message, :user, chat:, content: "How do I rotate a token?") }
  let(:assistant_message) { create(:message, :assistant, chat:, content: "Open the channel and rotate it.") }

  describe ".call" do
    it "creates a production example suite and chat-sourced test case", :aggregate_failures do
      result = service_call

      expect(result).to be_created
      expect(result.test_suite.name).to eq("Production examples - #{agent.name}")
      expect(result.test_suite.source_metadata).to include(
        "source" => described_class::SUITE_SOURCE,
        "agent_id" => agent.id,
      )
      expect(result.test_case).to have_attributes(
        prompt: "How do I rotate a token?",
        expected_answer: "Open the channel and rotate it.",
        match_type: "semantic",
        category: "production",
        source_type: "chat",
        scenario_key: "chat-#{chat.id}-message-#{assistant_message.id}",
      )
    end

    it "records chat provenance on the promoted test case", :aggregate_failures do
      result = service_call

      expect(result.test_case.source_metadata).to include(
        "source" => "chat",
        "chat_id" => chat.id,
        "chat_title" => "Support example",
        "chat_execution_context" => "playground",
        "agent_id" => agent.id,
        "prompt_message_id" => prompt_message.id,
        "assistant_message_id" => assistant_message.id,
        "promoted_by_user_id" => user.id,
      )
      expect(result.test_case.source_metadata["feedback"]).to eq({})
    end

    it "reuses the same promoted test case for the same assistant message", :aggregate_failures do
      first_result = service_call
      first_result.test_case.update!(expected_answer: "Outdated")

      second_result = described_class.call(chat:, assistant_message:, user:)

      expect(second_result).not_to be_created
      expect(second_result.test_case.id).to eq(first_result.test_case.id)
      expect(second_result.test_case.expected_answer).to eq("Open the channel and rotate it.")
    end

    it "uses negative feedback comments as the expected answer", :aggregate_failures do
      feedback = create(
        :message_feedback,
        :negative,
        message: assistant_message,
        user:,
        comment: "The correct answer must mention the API Tokens panel.",
      )

      result = service_call

      expect(result.test_case.expected_answer).to eq("The correct answer must mention the API Tokens panel.")
      expect(result.test_case.source_metadata["feedback"]).to include(
        "id" => feedback.id,
        "value" => "negative",
        "category" => "incorrect",
        "comment" => "The correct answer must mention the API Tokens panel.",
      )
    end

    it "keeps the assistant response when negative feedback has no comment", :aggregate_failures do
      create(:message_feedback, :negative, message: assistant_message, user:, comment: nil)

      result = service_call

      expect(result.test_case.expected_answer).to eq("Open the channel and rotate it.")
      expect(result.test_case.source_metadata["feedback"]).to include(
        "value" => "negative",
        "category" => "incorrect",
      )
    end

    it "rejects chats without agents" do
      chat.update!(agent: nil)

      expect { service_call }.to raise_error(ArgumentError, "Only chats backed by an agent can be promoted.")
    end

    it "rejects non-assistant messages" do
      expect do
        described_class.call(chat:, assistant_message: prompt_message, user:)
      end.to raise_error(ArgumentError, "Only assistant messages can be promoted.")
    end

    it "rejects missing assistant messages" do
      expect do
        described_class.call(chat:, assistant_message: nil, user:)
      end.to raise_error(ArgumentError, "Only assistant messages can be promoted.")
    end

    it "rejects assistant messages from another chat" do
      other_message = create(:message, :assistant, content: "Wrong chat")

      expect do
        described_class.call(chat:, assistant_message: other_message, user:)
      end.to raise_error(ArgumentError, "Message does not belong to this chat.")
    end

    it "rejects assistant messages without a preceding user prompt" do
      prompt_message.destroy!

      expect do
        service_call
      end.to raise_error(ArgumentError, "Promoted assistant messages need a preceding user prompt.")
    end

    it "rejects blank expected answers" do
      assistant_message.update!(content: "")

      expect do
        service_call
      end.to raise_error(ArgumentError, "Promoted test cases need an expected answer.")
    end
  end
end
