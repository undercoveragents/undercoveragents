# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chats::VisibleMessageLoader do
  describe ".load" do
    it "returns an empty collection without a chat" do
      expect(described_class.load(nil)).to eq([])
    end

    it "preloads tool_calls and the chat association without extra queries" do
      chat = create(:chat)
      assistant_message = create(:message, chat:, role: "assistant")
      create(:tool_call, message: assistant_message)
      create(:message, chat:, role: "user")

      messages = described_class.load(chat)

      assistant = messages.detect(&:assistant?)
      tool_call = assistant.tool_calls.first

      aggregate_failures do
        expect(messages.size).to eq(2)
        expect(assistant.association(:tool_calls).loaded?).to be(true)
        expect(tool_call.association(:message).loaded?).to be(true)
        expect(tool_call.message).to equal(assistant)
        expect(tool_call.message.association(:chat).loaded?).to be(true)
        expect(tool_call.message.chat).to eq(chat)
        messages.each do |message|
          expect(message.association(:chat).loaded?).to be(true)
          expect(message.chat).to eq(chat)
        end
      end
    end

    it "preloads attachment blobs for user messages when requested" do
      chat = create(:chat)
      user_message = create(:message, chat:, role: "user")
      user_message.attachments.attach(
        io: StringIO.new("hi"),
        filename: "hi.txt",
        content_type: "text/plain",
      )

      messages = described_class.load(chat, include_attachments: true)
      user = messages.detect(&:user?)

      expect(user.association(:attachments_attachments).loaded?).to be(true)
    end
  end
end
