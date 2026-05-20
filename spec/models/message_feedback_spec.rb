# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageFeedback do
  describe "validations" do
    let(:user) { create(:user) }
    let(:chat) { create(:chat, :user_context, user:) }
    let(:assistant_message) { create(:message, :assistant, chat:) }

    it "assigns the chat from the message" do
      feedback = described_class.create!(message: assistant_message, user:, value: "positive")

      expect(feedback.chat).to eq(chat)
    end

    it "clears category and comment for positive feedback" do
      feedback = described_class.create!(
        message: assistant_message,
        user:,
        value: "positive",
        category: "incorrect",
        comment: "Needs work",
      )

      expect(feedback.category).to be_nil
      expect(feedback.comment).to be_nil
      expect(feedback).to be_positive
      expect(feedback).not_to be_negative
    end

    it "rejects non-assistant messages" do
      user_message = create(:message, :user, chat:)
      feedback = described_class.new(message: user_message, user:, value: "negative", category: "incorrect")

      expect(feedback).not_to be_valid
      expect(feedback.errors[:message]).to include("must be an assistant message")
    end

    it "rejects feedback without a message" do
      feedback = described_class.new(user:, value: "positive")

      expect(feedback).not_to be_valid
      expect(feedback.chat).to be_nil
      expect(feedback.errors[:message]).to include("must be an assistant message")
    end

    it "rejects chats that do not match the message chat" do
      other_chat = create(:chat, :user_context, user:)
      feedback = described_class.new(
        message: assistant_message,
        chat: other_chat,
        user:,
        value: "negative",
        category: "incorrect",
      )

      expect(feedback).not_to be_valid
      expect(feedback.errors[:chat]).to include("must match the message chat")
    end
  end
end
