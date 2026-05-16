# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentDesigner::ReadAgentChatTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, tenant:, role: :admin) }
  let(:runtime_context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: nil,
      user:,
      tenant:,
      operation:,
    )
  end

  def create_inspectable_chat(agent:, user:)
    chat = create(:chat, agent:, user:, execution_context: :system, title: "Inspect me")
    message = create(
      :message,
      chat:,
      role: :assistant,
      content: "Troubleshooting response",
      input_tokens: 12,
      output_tokens: 7,
      duration_ms: 150,
    )
    create(:tool_call, message:, name: "read_agent", tool_call_id: "call-1", arguments: { agent_id: agent.id })
    chat
  end

  it "lists recent chats for the current agent" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")
    older_chat = create(:chat, agent:, user:, execution_context: :user, title: "Older chat", updated_at: 2.hours.ago)
    latest_chat = create(:chat, agent:, user:, execution_context: :system, title: "Latest chat", updated_at: 1.hour.ago)
    create(:message, chat: older_chat, role: :user, content: "hello")
    create(:message, chat: latest_chat, role: :assistant, content: "world", input_tokens: 10, output_tokens: 5)

    result = described_class.new(runtime_context:, current_agent: agent).execute(selector: "recent")

    expect(result).to include("## Recent Agent Chats (2)")
    expect(result).to include("chat_id=`#{latest_chat.id}`")
    expect(result).to include("title=\"Latest chat\"")
    expect(result).to include("execution_context=system")
  end

  it "reads one specific chat with inspector-style details" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")
    chat = create_inspectable_chat(agent:, user:)

    result = described_class.new(runtime_context:, current_agent: agent).execute(chat_id: chat.id, detail: "full")

    expect(result).to include(
      "## Agent Chat",
      "- chat_id: `#{chat.id}`",
      "## Messages (showing 1)",
      "### Message 1",
      "tool_call_details",
      "Troubleshooting response",
    )
  end

  it "rejects chats that belong to another agent" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")
    other_agent = create(:agent, operation:, name: "Other", model_id: "gpt-4.1")
    foreign_chat = create(:chat, agent: other_agent, user:, execution_context: :user)

    result = described_class.new(runtime_context:, current_agent: agent).execute(chat_id: foreign_chat.id)

    expect(result).to eq("No chat with ID '#{foreign_chat.id}' was found for 'Debugger'.")
  end

  it "returns a helpful message when there is no current agent" do
    result = described_class.new(runtime_context:).execute

    expect(result).to eq(
      "No current agent is available. Pass agent_id after creating one or open an agent page first.",
    )
  end

  it "reads the latest chat by default" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")
    latest_chat = create_inspectable_chat(agent:, user:)

    result = described_class.new(runtime_context:, current_agent: agent).execute

    expect(result).to include("## Agent Chat", "- chat_id: `#{latest_chat.id}`")
  end

  it "returns an explicit message when the latest chat is missing" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")

    result = described_class.new(runtime_context:, current_agent: agent).execute(selector: "latest")

    expect(result).to eq("No chats found for 'Debugger'.")
  end

  it "rescues selector validation errors" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")

    result = described_class.new(runtime_context:, current_agent: agent).execute(selector: "bogus")

    expect(result).to eq("Error: selector must be one of: latest, recent")
  end

  it "rescues unexpected errors while reading chats" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")
    tool = described_class.new(runtime_context:, current_agent: agent)
    allow(tool).to receive(:agent_chat_scope).and_raise(StandardError, "boom")

    expect(tool.execute).to eq("Error reading agent chats: boom")
  end

  it "falls through when a formatter returns an unexpected selector" do
    agent = create(:agent, operation:, name: "Debugger", model_id: "gpt-4.1")
    tool = described_class.new(runtime_context:, current_agent: agent)
    formatter = instance_double(AgentDesigner::ChatDebugFormatter, normalized_selector: "unexpected")

    allow(tool).to receive(:formatter).and_return(formatter)

    expect(tool.execute).to be_nil
  end
end
