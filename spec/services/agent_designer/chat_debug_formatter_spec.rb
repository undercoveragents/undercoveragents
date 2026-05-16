# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentDesigner::ChatDebugFormatter do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:agent) { create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1") }

  it "formats a chat with parent, child, and omitted message details" do
    parent_chat = create(:chat, agent: nil, title: "Parent chat")
    chat = create(:chat, agent:, parent_chat:, title: "Main chat")
    create(:message, chat:, content: "first")
    create(:message, chat:, content: "second")
    child_chat = create(:chat, agent: nil, parent_chat: chat, title: "Child chat")
    allow(chat).to receive(:model).and_return(nil)

    result = described_class.new(agent:).format_chat(chat, message_limit: 1)

    expect(result).to include(
      "## Parent Chat",
      "- title: Parent chat",
      "- agent: -",
      "## Child Chats (1)",
      "chat_id=`#{child_chat.id}`",
      "agent=\"-\"",
      "messages=0",
      "- earlier_messages_omitted: 1",
    )
  end

  it "formats empty chats without parent or child sections" do
    chat = create(:chat, agent:, title: "Empty chat")
    allow(chat).to receive(:model).and_return(nil)

    result = described_class.new(agent:).format_chat(chat)

    expect(result).to include("## Messages (showing 0)", "No messages found.")
    expect(result).not_to include("## Parent Chat", "## Child Chats")
  end

  it "formats recent chats and includes parent chat ids when present" do
    parent_chat = create(:chat, agent:, title: "Parent")
    child_chat = create(:chat, agent:, parent_chat:, title: "Child")

    result = described_class.new(agent:).format_recent_chats([child_chat])

    expect(result).to include("## Recent Agent Chats (1)", "parent_chat_id=#{parent_chat.id}")
  end

  it "handles empty recent chat lists and invalid selectors" do
    formatter = described_class.new(agent:)

    expect(formatter.format_recent_chats([])).to eq("No chats found for 'Debugger'.")
    expect { formatter.normalized_selector("bogus") }.to raise_error(ArgumentError, /selector must be one of/)
  end

  it "renders parent and child agent names when they are present" do
    parent_agent = create(:agent, operation:, name: "Parent Agent", model_id: "gpt-4.1")
    child_agent = create(:agent, operation:, name: "Child Agent", model_id: "gpt-4.1")
    parent_chat = create(:chat, agent: parent_agent, title: "Parent")
    chat = create(:chat, agent:, parent_chat:, title: "Main")
    create(:chat, agent: child_agent, parent_chat: chat, title: "Child")

    result = described_class.new(agent:).format_chat(chat)

    expect(result).to include("- agent: Parent Agent", "agent=\"Child Agent\"")
  end
end
