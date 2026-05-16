# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentDesigner::ChatMessageFormatter do
  it "formats a basic message without tool details or model fallbacks" do
    chat = create(:chat)
    message = create(:message, chat:, model: nil, content: "hello")
    allow(chat).to receive(:model).and_return(nil)
    allow(message).to receive(:chat).and_return(chat)

    result = described_class.new(full: false).format_message(message, position: 1).join("\n")

    expect(result).to include("### Message 1", "- model: -", "  content: hello")
    expect(result).not_to include("- tool_call_details:")
  end

  it "formats a tool message with thinking and raw content details" do
    chat = create(:chat)
    message = create(
      :message,
      :tool,
      chat:,
      content: "first line\nsecond line",
      thinking_text: "tool thinking",
      thinking_signature: "sig-123",
      content_raw: { "status" => "ok" },
    )

    result = described_class.new(full: false).format_message(message, position: 2).join("\n")

    expect(result).to include(
      "### Message 2",
      "- tool_call_id: -",
      "  thinking: tool thinking",
      "  thinking_signature: sig-123",
      "  content:\n    first line\n    second line",
      "  content_raw:\n    {",
    )
  end

  it "prefers an explicit message model when present" do
    chat = create(:chat)
    model = create(:model, model_id: "message-model")
    message = create(:message, chat:, model:, content: "hello")

    result = described_class.new(full: false).format_message(message, position: 3).join("\n")

    expect(result).to include("- model: message-model")
  end

  it "handles messages without an attached chat" do
    message = create(:message, chat: create(:chat), model: nil, content: "hello")
    allow(message).to receive(:chat).and_return(nil)

    result = described_class.new(full: false).format_message(message, position: 4).join("\n")

    expect(result).to include("- model: -")
  end
end
