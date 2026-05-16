# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chats::SubagentBranchResolver do
  def build_parent_chat_with_subagent_agents
    operation = OperationFactoryHelper.default_operation
    parent_agent = create(:agent, operation:)
    mission_designer = create(:agent, operation:, name: "Mission Designer")
    parent_agent.update!(subagent_ids: [mission_designer.id])

    { parent_agent:, mission_designer: }
  end

  def build_parent_chat(parent_agent:)
    create(:chat, :user_context, user: create(:user), agent: parent_agent)
  end

  def build_parent_subagent_call_message(chat:)
    assistant_message = create(
      :message,
      :assistant,
      chat:,
      content: nil,
      created_at: Time.zone.parse("2026-04-24 12:00:00"),
    )
    create(
      :tool_call,
      message: assistant_message,
      name: "ask_agent_mission_designer",
      created_at: Time.zone.parse("2026-04-24 12:00:01"),
    )
    create(:message, :user, chat:, content: "Next", created_at: Time.zone.parse("2026-04-24 12:00:05"))
  end

  def build_parent_chat_with_subagent_call(child_chat_at:)
    agents = build_parent_chat_with_subagent_agents
    chat = build_parent_chat(parent_agent: agents[:parent_agent])
    build_parent_subagent_call_message(chat:)
    create(
      :chat,
      parent_chat: chat,
      agent: agents[:mission_designer],
      title: "Subagent: Mission Designer",
      created_at: child_chat_at,
    )

    chat
  end

  describe ".tool_call_identity" do
    it "handles nil, tool_call_id-only, and object fallback inputs", :aggregate_failures do
      tool_call_with_runtime_id = Struct.new(:tool_call_id).new("runtime-call-1")
      fallback_tool_call = Object.new

      expect(described_class.tool_call_identity(nil)).to be_nil
      expect(described_class.tool_call_identity(tool_call_with_runtime_id)).to eq("runtime-call-1")
      expect(described_class.tool_call_identity(fallback_tool_call)).to eq(fallback_tool_call.object_id)
    end
  end

  describe ".child_chat_assignments_for" do
    it "uses default visible messages and ignores child chats outside the message window" do
      chat = build_parent_chat_with_subagent_call(child_chat_at: Time.zone.parse("2026-04-24 12:00:10"))

      expect(described_class.child_chat_assignments_for(chat)).to eq({})
    end

    it "returns no assignments when the parent chat has no agent" do
      chat = create(:chat, :user_context, user: create(:user), agent: nil)
      assistant_message = create(:message, :assistant, chat:, content: nil)
      create(:tool_call, message: assistant_message, name: "ask_agent_mission_designer")
      create(:chat, parent_chat: chat, agent: create(:agent), title: "Detached child")

      expect(described_class.child_chat_assignments_for(chat)).to eq({})
    end
  end

  describe "private assignment fallbacks" do
    it "skips tool calls without a resolved subagent or a matching child chat", :aggregate_failures do
      resolver = described_class.new(instance_double(Chat), messages: [:sentinel])
      tool_call = Struct.new(:name).new("ask_agent_missing")
      child_chat = Struct.new(:agent_id).new(999)

      allow(resolver).to receive(:subagent_index).and_return({})
      expect(resolver.send(:assign_child_chats_to_tool_calls, [tool_call], [child_chat])).to eq({})

      allow(resolver).to receive(:subagent_index).and_return({ tool_call.name => Struct.new(:id).new(123) })
      expect(resolver.send(:assign_child_chats_to_tool_calls, [tool_call], [child_chat])).to eq({})
    end
  end
end
