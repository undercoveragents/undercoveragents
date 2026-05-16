# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chats::MessageCompactor do
  let(:chat) { create(:chat) }

  def add_tool_call(chat, tool_name, arguments, result_content = "result", assistant_content: "")
    assistant = chat.messages.create!(role: :assistant, content: assistant_content)
    tool_call = assistant.tool_calls.create!(
      tool_call_id: "call_#{SecureRandom.hex(4)}",
      name: tool_name,
      arguments:,
    )
    tool_message = chat.messages.create!(
      role: :tool,
      content: result_content,
      tool_call_id: tool_call.id,
    )
    [tool_call, tool_message]
  end

  describe "#policy_for" do
    it "returns the default policy for unknown tools" do
      expect(described_class.new(chat).policy_for("unknown_tool")).to eq(described_class::DEFAULT_POLICY)
    end

    it "resolves builtin tool policies from BuiltinTools::Registry" do
      definition = BuiltinTools::Registry.definition_for_runtime_name("add_node")
      expect(definition&.compaction_policy).to eq(:drop_all)
      expect(described_class.new(chat).policy_for("add_node")).to eq(:drop_all)
    end

    it "resolves mission designer read-only tools to :replace_on_assistant_reply" do
      expect(described_class.new(chat).policy_for("read_mission_flow")).to eq(:replace_on_assistant_reply)
    end
  end

  describe "#stale_message_ids" do
    context "with a builtin :replace_on_assistant_reply workflow tool" do
      it "keeps results until a user-visible assistant reply appears, then stubs older results" do
        _, m1 = add_tool_call(chat, "read_mission_flow", { "x" => 1 })
        _, m2 = add_tool_call(chat, "read_mission_flow", { "x" => 2 })
        chat.messages.create!(role: :assistant, content: "Here is the plan.")
        _, m3 = add_tool_call(chat, "read_mission_flow", { "x" => 3 })

        stale = described_class.new(chat).stale_message_ids
        expect(stale).to contain_exactly(m1.id, m2.id)
        expect(stale).not_to include(m3.id)
      end

      it "keeps every result when no user-visible assistant reply has landed yet" do
        _, m1 = add_tool_call(chat, "read_mission_flow", { "x" => 1 })
        _, m2 = add_tool_call(chat, "read_mission_flow", { "x" => 2 })

        stale = described_class.new(chat).stale_message_ids
        expect(stale).not_to include(m1.id, m2.id)
      end

      it "ignores tool-call-only assistant frames when determining reply boundaries" do
        _, m1 = add_tool_call(chat, "read_mission_flow", { "x" => 1 })
        chat.messages.create!(role: :assistant, content: "")
        _, m2 = add_tool_call(chat, "read_mission_flow", { "x" => 2 })

        stale = described_class.new(chat).stale_message_ids
        expect(stale).not_to include(m1.id, m2.id)
      end

      it "does not stub orphan tool messages even when a reply boundary exists" do
        _, m1 = add_tool_call(chat, "read_mission_flow", { "x" => 1 })
        orphan = chat.messages.create!(role: :tool, content: "orphan", tool_call_id: nil)
        chat.messages.create!(role: :assistant, content: "Done.")

        stale = described_class.new(chat).stale_message_ids
        expect(stale).to include(m1.id)
        expect(stale).not_to include(orphan.id)
      end

      it "does not affect tool results that use other compaction policies" do
        _, kept = add_tool_call(chat, "add_node", { "type" => "llm" })
        chat.messages.create!(role: :assistant, content: "Added.")
        # add_node uses :drop_all which still stubs this, but not via the
        # assistant-reply path. We just verify the assistant-reply pass alone
        # does not touch it.
        compactor = described_class.new(chat)
        expect(compactor.send(:stale_ids_for_assistant_reply_policy)).to eq([])
        expect(compactor.stale_message_ids).to include(kept.id)
      end
    end

    context "with the default :replace_by_args policy" do
      it "keeps the latest per (name, args) and stubs prior identical calls" do
        _, m1 = add_tool_call(chat, "info", { "type" => "llm" })
        _, m2 = add_tool_call(chat, "info", { "type" => "llm" })
        _, m3 = add_tool_call(chat, "info", { "type" => "condition" })

        stale = described_class.new(chat).stale_message_ids
        expect(stale).to contain_exactly(m1.id)
        expect(stale).not_to include(m2.id, m3.id)
      end
    end

    context "with a builtin :drop_all tool" do
      it "stubs every call, including the most recent" do
        _, m1 = add_tool_call(chat, "add_node", { "type" => "llm" })
        _, m2 = add_tool_call(chat, "add_node", { "type" => "condition" })

        stale = described_class.new(chat).stale_message_ids
        expect(stale).to contain_exactly(m1.id, m2.id)
      end

      it "stubs a single call as well" do
        _, m1 = add_tool_call(chat, "add_node", {})

        expect(described_class.new(chat).stale_message_ids).to contain_exactly(m1.id)
      end
    end

    context "with a user tool exposing tool_compaction_policy" do
      let(:toolable_class) do
        Class.new do
          def tool_compaction_policy; end
        end
      end

      it "uses the configured policy when resolvable for the chat agent" do
        toolable = instance_double(toolable_class, tool_compaction_policy: "keep_all")
        allow(ToolCalls::DisplayMetadataResolver).to receive(:tool_record_for)
          .with("sql_query_myquery", chat:)
          .and_return(instance_double(Tool, toolable:))

        add_tool_call(chat, "sql_query_myquery", {})
        add_tool_call(chat, "sql_query_myquery", {})

        expect(described_class.new(chat).stale_message_ids).to be_empty
      end

      it "falls back to the default policy when the configured value is invalid" do
        toolable = instance_double(toolable_class, tool_compaction_policy: "nonsense")
        allow(ToolCalls::DisplayMetadataResolver).to receive(:tool_record_for)
          .and_return(instance_double(Tool, toolable:))

        _, m1 = add_tool_call(chat, "sql_query_myquery", { "q" => 1 })
        _, m2 = add_tool_call(chat, "sql_query_myquery", { "q" => 1 })

        stale = described_class.new(chat).stale_message_ids
        expect(stale).to contain_exactly(m1.id)
        expect(stale).not_to include(m2.id)
      end

      it "falls back to the default policy when the configured value is blank" do
        toolable = instance_double(toolable_class, tool_compaction_policy: "")
        allow(ToolCalls::DisplayMetadataResolver).to receive(:tool_record_for)
          .and_return(instance_double(Tool, toolable:))

        _, m1 = add_tool_call(chat, "unknown_runtime_tool", {})
        _, m2 = add_tool_call(chat, "unknown_runtime_tool", {})

        stale = described_class.new(chat).stale_message_ids
        expect(stale).to contain_exactly(m1.id)
        expect(stale).not_to include(m2.id)
      end

      it "falls back to the default policy when the toolable does not expose the policy method" do
        allow(ToolCalls::DisplayMetadataResolver).to receive(:tool_record_for)
          .and_return(instance_double(Tool, toolable: Object.new))

        _, m1 = add_tool_call(chat, "unknown_runtime_tool", {})
        _, m2 = add_tool_call(chat, "unknown_runtime_tool", {})

        stale = described_class.new(chat).stale_message_ids
        expect(stale).to contain_exactly(m1.id)
        expect(stale).not_to include(m2.id)
      end
    end

    it "ignores non-tool messages" do
      chat.messages.create!(role: :user, content: "hi")
      chat.messages.create!(role: :assistant, content: "hello")

      expect(described_class.new(chat).stale_message_ids).to be_empty
    end

    it "ignores tool messages that have no associated tool_call" do
      chat.messages.create!(role: :tool, content: "orphan result", tool_call_id: nil)

      expect(described_class.new(chat).stale_message_ids).to be_empty
    end
  end
end
