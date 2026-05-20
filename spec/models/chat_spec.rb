# frozen_string_literal: true

# == Schema Information
#
# Table name: chats
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  child_chats_count       :integer          default(0), not null
#  execution_context       :string           default("playground"), not null
#  messages_count          :integer          default(0), not null
#  status                  :string           default("idle"), not null
#  title                   :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  agent_id                :bigint
#  channel_conversation_id :bigint
#  channel_id              :bigint
#  channel_target_id       :bigint
#  client_id               :bigint
#  mission_id              :bigint
#  model_id                :bigint
#  parent_chat_id          :bigint
#  telegram_chat_id        :bigint
#  user_id                 :bigint
#
# Indexes
#
#  index_chats_on_agent_id                 (agent_id)
#  index_chats_on_channel_conversation_id  (channel_conversation_id)
#  index_chats_on_channel_id               (channel_id)
#  index_chats_on_channel_target_id        (channel_target_id)
#  index_chats_on_client_id                (client_id)
#  index_chats_on_execution_context        (execution_context)
#  index_chats_on_mission_id               (mission_id)
#  index_chats_on_model_id                 (model_id)
#  index_chats_on_parent_chat_id           (parent_chat_id)
#  index_chats_on_telegram_chat_id         (telegram_chat_id)
#  index_chats_on_user_id                  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (agent_id => agents.id)
#  fk_rails_...  (channel_conversation_id => channel_conversations.id)
#  fk_rails_...  (channel_id => channels.id)
#  fk_rails_...  (channel_target_id => channel_targets.id)
#  fk_rails_...  (client_id => clients.id)
#  fk_rails_...  (mission_id => missions.id)
#  fk_rails_...  (model_id => models.id)
#  fk_rails_...  (parent_chat_id => chats.id)
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe Chat do
  def build_application_branch_chat(agent_name: "Mission Designer")
    parent_chat = create(:chat, execution_context: :application, user: create(:user))
    operation = create(:operation, tenant: parent_chat.user.tenant)
    chat = create(
      :chat,
      execution_context: :application,
      user: parent_chat.user,
      parent_chat:,
      agent: create(:agent, name: agent_name, operation:),
    )

    [parent_chat, chat]
  end

  describe "associations" do
    it { is_expected.to belong_to(:agent).optional }
    it { is_expected.to belong_to(:parent_chat).class_name("Chat").optional }
    it { is_expected.to have_many(:child_chats).class_name("Chat").dependent(:nullify) }
    it { is_expected.to have_many(:messages) }
  end

  describe "enums" do
    subject(:chat) { described_class.new }

    it {
      expect(chat).to define_enum_for(:status).with_values(
        idle: "idle", streaming: "streaming", cancelled: "cancelled",
      ).backed_by_column_of_type(:string)
    }

    it {
      expect(chat).to define_enum_for(:execution_context).with_values(
        playground: "playground", application: "application", test: "test", system: "system",
        channel: "channel", user: "user", telegram: "telegram", mission: "mission",
      ).backed_by_column_of_type(:string).with_default(:playground)
    }
  end

  describe "#response_context" do
    it "returns application for application chats" do
      expect(build(:chat, :application_context).response_context).to eq(:application)
    end

    it "returns mission_designer for system mission chats" do
      expect(build(:chat, :system_context, mission: build_stubbed(:mission)).response_context).to eq(:mission_designer)
    end

    it "returns user for user chats" do
      expect(build(:chat, :user_context).response_context).to eq(:user)
    end

    it "returns nil for unsupported contexts" do
      expect(build(:chat, :test_context).response_context).to be_nil
    end
  end

  describe "scopes" do
    describe ".for_agent" do
      it "returns chats for the given agent" do
        agent = create(:agent)
        chat = create(:chat, agent:)
        create(:chat) # other chat without agent

        expect(described_class.for_agent(agent)).to eq([chat])
      end
    end

    describe ".recent" do
      it "orders by updated_at descending" do
        old_chat = create(:chat)
        new_chat = create(:chat)
        old_chat.update!(updated_at: 1.day.ago)

        expect(described_class.recent).to eq([new_chat, old_chat])
      end
    end
  end

  describe "#display_title" do
    it "returns the title when present" do
      chat = build(:chat, title: "My Chat")
      expect(chat.display_title).to eq("My Chat")
    end

    it "returns default title when title is blank" do
      chat = build(:chat, title: nil)
      expect(chat.display_title).to eq(described_class::DEFAULT_TITLE)
    end
  end

  describe "#display_title_for_ui" do
    it "falls back to the default title when stripping the application agent prefix leaves a blank title" do
      agent = build_stubbed(:agent, name: "Agent Alpha")
      chat = build(:chat, :application_context, agent:, title: "Agent Alpha —")

      expect(chat.display_title_for_ui).to eq(described_class::DEFAULT_TITLE)
    end

    it "leaves the visible title unchanged when the application chat has no named agent" do
      chat = build(:chat, :application_context, agent: nil, title: "Standalone Title")

      expect(chat.display_title_for_ui).to eq("Standalone Title")
    end
  end

  describe "#playground_agent_supported?" do
    it "returns nil when no agent is assigned" do
      expect(build(:chat, agent: nil).playground_agent_supported?).to be_nil
    end

    it "delegates compatibility checks to the assigned agent" do
      agent = build_stubbed(:agent)
      allow(agent).to receive(:playground_compatible?).and_return(false)

      expect(build(:chat, agent:).playground_agent_supported?).to be(false)
      expect(agent).to have_received(:playground_compatible?)
    end
  end

  describe "#ask" do
    it "forwards keyword arguments while scoping Current.chat to the call" do
      previous_chat = build_stubbed(:chat, id: 999)
      chat = create(:chat)
      seen_chat = nil
      allow(chat).to receive(:setup_duration_tracking) do
        chat.instance_variable_set(:@duration_tracking_initialized, true)
      end
      allow(chat).to receive(:complete) do
        seen_chat = Current.chat
        :ok
      end

      begin
        Current.chat = previous_chat

        result = chat.ask("Hello", with: nil)

        expect(result).to eq(:ok)
        expect(seen_chat).to eq(chat)
        expect(Current.chat).to eq(previous_chat)
        expect(chat.messages.order(:id).last.role).to eq("user")
      ensure
        Current.chat = nil
      end
    end

    it "delegates to the routing executor when model routing is enabled" do
      chat = create(:chat)
      executor = instance_double(Llm::ModelRoutingExecutor, enabled?: true)
      chat.instance_variable_set(:@duration_tracking_initialized, true)
      chat.instance_variable_set(:@model_routing_executor, executor)
      allow(executor).to receive(:ask).with("Hello", with: nil).and_return(:routed)

      expect(chat.ask("Hello", with: nil)).to eq(:routed)
    end
  end

  describe "model routing helpers" do
    # rubocop:disable RSpec/ExampleLength
    it "builds and clears the routing executor based on primary model inputs" do
      tenant = create(:tenant)
      connector = create(:connector, :llm_provider, :enabled, tenant:)
      model = create(:model, model_id: "gpt-4.1", provider: connector.provider)
      chat = create(:chat, user: create(:user, tenant:))

      chat.configure_model_routing!(
        primary_connector: connector,
        primary_model_id: nil,
        primary_model_record: model,
        routing_config: {},
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )
      expect(chat.instance_variable_get(:@model_routing_executor)).to be_nil

      chat.configure_model_routing!(
        primary_connector: connector,
        primary_model_id: model.model_id,
        primary_model_record: model,
        routing_config: { "strategy" => "fallback" },
        temperature: 0.2,
        thinking_effort: "low",
        thinking_budget: 64,
        custom_params: { "top_p" => 0.9 },
        tools_present: true,
      )

      executor = chat.instance_variable_get(:@model_routing_executor)
      expect(executor).to be_a(Llm::ModelRoutingExecutor)
    end
    # rubocop:enable RSpec/ExampleLength

    it "temporarily bypasses routing while preserving the previous flag value" do
      chat = create(:chat)
      chat.instance_variable_set(:@_bypass_model_routing, false)
      seen_flag = nil
      allow(chat).to receive(:ask) do
        seen_flag = chat.instance_variable_get(:@_bypass_model_routing)
        :ok
      end

      expect(chat.send(:perform_ask_without_routing, "Hello", with: nil)).to eq(:ok)
      expect(seen_flag).to be(true)
      expect(chat.instance_variable_get(:@_bypass_model_routing)).to be(false)
    end

    # rubocop:disable RSpec/MultipleExpectations
    it "resolves routing connectors from the available tenant contexts" do
      tenant = create(:tenant)
      connector = create(:connector, :llm_provider, :enabled, tenant:)
      mission = create(:mission, operation: create(:operation, tenant:))
      agent = create(:agent, operation: create(:operation, tenant:))
      parent_agent = create(:agent, operation: create(:operation, tenant:))
      parent_chat = create(:chat, agent: parent_agent)

      expect(create(:chat, agent:).send(:routing_tenant)).to eq(agent.operation.tenant)
      expect(create(:chat, mission:).send(:routing_tenant)).to eq(mission.operation.tenant)

      user_chat = create(:chat, user: create(:user, tenant:))
      expect(user_chat.send(:routing_tenant)).to eq(tenant)
      expect(user_chat.send(:resolve_routing_connector, connector.id)).to eq(connector)

      child_chat = create(:chat, parent_chat:)
      expect(child_chat.send(:routing_tenant)).to eq(parent_agent.operation.tenant)
      expect(build(:chat).send(:resolve_routing_connector, connector.id)).to be_nil
    end
    # rubocop:enable RSpec/MultipleExpectations

    it "returns nil for a parent chat without an operation-backed agent" do
      chat = build(:chat)
      orphan_agent = instance_double(Agent, operation: nil)
      allow(chat).to receive(:parent_chat).and_return(instance_double(described_class, agent: orphan_agent))

      expect(chat.send(:parent_chat_tenant)).to be_nil
    end
  end

  describe "#with_current_chat_context" do
    it "sets Current.chat for the duration of the block and restores the previous value" do
      previous_chat = build_stubbed(:chat, id: 999)
      chat = build_stubbed(:chat, id: 123)
      Current.chat = previous_chat
      seen_chat = nil

      result = chat.send(:with_current_chat_context) do
        seen_chat = Current.chat
        :ok
      end

      expect(result).to eq(:ok)
      expect(seen_chat).to eq(chat)
      expect(Current.chat).to eq(previous_chat)
    end
  end

  describe "#set_default_title" do
    it "sets the default title on new records" do
      chat = described_class.new
      expect(chat.title).to eq(described_class::DEFAULT_TITLE)
    end

    it "does not override an existing title" do
      chat = described_class.new(title: "Custom Title")
      expect(chat.title).to eq("Custom Title")
    end
  end

  describe "#broadcast_status_update" do
    it "does not raise an error" do
      chat = create(:chat)
      expect { chat.broadcast_status_update }.not_to raise_error
    end

    it "broadcasts status through the chat UI stream" do
      chat = create(:chat, execution_context: :application, user: create(:user))
      allow(ActionCable.server).to receive(:broadcast)

      chat.broadcast_status_update

      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(
          type: "status",
          chat_id: chat.id,
          status: "idle",
          phase: nil,
        ),
      )
    end

    it "includes child chat metadata for branch streams" do
      parent_chat, chat = build_application_branch_chat
      allow(ActionCable.server).to receive(:broadcast)

      chat.broadcast_status_update

      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(
          type: "status",
          chat_id: chat.id,
          status: "idle",
          phase: nil,
          parent_chat_id: parent_chat.id,
          agent_name: "Mission Designer",
        ),
      )
    end

    it "passes through an explicit phase when provided" do
      chat = create(:chat, execution_context: :playground)
      allow(ActionCable.server).to receive(:broadcast)

      chat.broadcast_status_update(phase: :thinking)

      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "status", chat_id: chat.id, phase: :thinking),
      )
    end

    it "broadcasts status JSON for non-user execution contexts" do
      chat = create(:chat, execution_context: :playground)
      allow(ActionCable.server).to receive(:broadcast)
      chat.broadcast_status_update
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "status", chat_id: chat.id, status: chat.status),
      )
    end

    it "broadcasts status JSON for user execution context" do
      chat = create(:chat, execution_context: :user)
      allow(ActionCable.server).to receive(:broadcast)
      chat.broadcast_status_update
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "status", chat_id: chat.id, status: chat.status),
      )
    end
  end

  describe "#broadcast_title_update" do
    it "broadcasts title updates through the application UI stream for application chats with a user" do
      chat = create(:chat, :application_context, user: create(:user))
      allow(ActionCable.server).to receive(:broadcast)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      chat.broadcast_title_update

      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(
          type: "chat_title",
          chat_id: chat.id,
          target: chat.title_dom_id,
          title: chat.display_title_for_ui,
        ),
      )
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end

    it "uses the chat stream when the application chat has no user" do
      chat = create(:chat, :application_context, user: nil)
      allow(ActionCable.server).to receive(:broadcast)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      chat.broadcast_title_update

      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.stream_channel_name,
        hash_including(type: "chat_title", target: chat.title_dom_id),
      )
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end
  end

  describe ".user_stream_channel_name_for" do
    it "builds a stable user-scoped stream name" do
      user = build_stubbed(:user, id: 42)

      expect(described_class.user_stream_channel_name_for(user)).to eq("chat_user_stream_42")
      expect(described_class.user_stream_channel_name_for(42)).to eq("chat_user_stream_42")
    end
  end

  describe "#ui_stream_channel_name" do
    it "uses the user-scoped stream for user-owned chats" do
      chat = build(:chat, execution_context: :application, user: build_stubbed(:user, id: 7))

      expect(chat.ui_stream_channel_name).to eq("chat_user_stream_7")
    end

    it "falls back to the chat stream for chats without a user" do
      chat = build_stubbed(:chat, id: 9, execution_context: :playground, user: nil)

      expect(chat.ui_stream_channel_name).to eq("chat_stream_9")
    end

    it "uses the parent stream for child chats without their own user" do
      user = build_stubbed(:user, id: 8)
      parent_chat = build_stubbed(:chat, id: 10, execution_context: :application, user:)
      child_chat = build_stubbed(:chat, id: 11, parent_chat:, user: nil)

      expect(child_chat.ui_stream_channel_name).to eq("chat_user_stream_8")
    end
  end

  describe "#calculate_cost" do
    let(:model_record) do
      create(:model, pricing: {
               "text_tokens" => {
                 "standard" => {
                   "input_per_million" => "3.00",
                   "output_per_million" => "15.00",
                   "cached_input_per_million" => "1.50",
                   "cache_creation_per_million" => "3.75",
                 },
               },
             },)
    end

    let(:chat) { create(:chat, model: model_record) }

    it "sums the cost of all messages" do
      create(:message, chat:, model: model_record,
                       input_tokens: 1_000_000, output_tokens: 0,
                       cached_tokens: 0, cache_creation_tokens: 0,)
      create(:message, chat:, model: model_record,
                       input_tokens: 0, output_tokens: 1_000_000,
                       cached_tokens: 0, cache_creation_tokens: 0,)

      # First message: 1M input tokens * $3/M = $3.00
      # Second message: 1M output tokens * $15/M = $15.00
      expect(chat.calculate_cost).to eq(BigDecimal("18.0"))
    end

    it "returns 0 when there are no messages" do
      expect(chat.calculate_cost).to eq(0)
    end

    it "treats nil costs as 0" do
      chat_no_model = create(:chat)
      chat_no_model.update_column(:model_id, nil) # rubocop:disable Rails/SkipsModelValidations
      chat_no_model.reload
      create(:message, chat: chat_no_model, model: nil,
                       input_tokens: 100, output_tokens: 50,
                       cached_tokens: 0, cache_creation_tokens: 0,)

      expect(chat_no_model.calculate_cost).to eq(0)
    end
  end

  describe "#configure_for_agent" do
    let(:agent) { create(:agent) }
    let(:chat) { create(:chat) }

    before do
      allow(chat).to receive(:with_model)
      allow(chat).to receive(:with_temperature)
      allow(chat).to receive(:with_instructions)
      allow(chat).to receive(:with_tools)
    end

    it "sets context from the agent's LLM context" do
      allow(agent).to receive(:resolve_llm_context).and_return("ctx")
      chat.configure_for_agent(agent)
      expect(agent).to have_received(:resolve_llm_context)
      expect(chat.context).to eq("ctx")
    end

    it "calls with_model with the agent's model_id" do
      chat.configure_for_agent(agent)
      expect(chat).to have_received(:with_model).with(agent.model_id)
    end

    it "calls with_temperature with the agent's temperature" do
      chat.configure_for_agent(agent)
      expect(chat).to have_received(:with_temperature).with(agent.temperature)
    end

    it "applies instructions when the agent returns non-blank instructions" do
      allow(agent).to receive(:build_full_instructions).and_return("Be helpful")
      chat.configure_for_agent(agent)
      expect(chat).to have_received(:with_instructions).with("Be helpful")
    end

    it "skips with_instructions when the agent returns blank instructions" do
      allow(agent).to receive(:build_full_instructions).and_return("")
      chat.configure_for_agent(agent)
      expect(chat).not_to have_received(:with_instructions)
    end

    it "applies tools when the agent returns tools" do
      tool = instance_double(SubagentTool)
      allow(agent).to receive(:tools).and_return([tool])
      chat.configure_for_agent(agent)
      expect(chat).to have_received(:with_tools).with(tool)
    end

    it "skips with_tools when the agent has no tools" do
      allow(agent).to receive(:tools).and_return([])
      chat.configure_for_agent(agent)
      expect(chat).not_to have_received(:with_tools)
    end
  end

  describe "#enqueue_response!" do
    let(:agent) { create(:agent) }

    before do
      allow(ChatResponseJob).to receive(:perform_later)
    end

    it "enqueues a user chat response and updates streaming state" do
      chat = create(:chat, :user_context, user: create(:user), agent:)
      allow(chat).to receive(:broadcast_status_update)

      chat.enqueue_response!(content: "Hello", attachment_signed_ids: ["signed-1"])

      expect(ChatResponseJob).to have_received(:perform_later).with(
        chat.id,
        "Hello",
        ["signed-1"],
        tenant_id: chat.send(:response_job_tenant_id),
      )
      expect(chat.reload).to be_streaming
      expect(chat).to have_received(:broadcast_status_update)
    end

    it "enqueues a playground chat response" do
      chat = create(:chat, :playground_context, user: create(:user), agent:)
      allow(chat).to receive(:broadcast_status_update)

      chat.enqueue_response!(content: "Hello")

      expect(ChatResponseJob).to have_received(:perform_later).with(
        chat.id,
        "Hello",
        [],
        tenant_id: chat.send(:response_job_tenant_id),
      )
      expect(chat.reload).to be_streaming
      expect(chat).to have_received(:broadcast_status_update)
    end

    it "enqueues a mission designer chat response" do
      mission = create(:mission)
      chat = create(:chat, :system_context, user: create(:user), agent:, mission:)
      allow(chat).to receive(:broadcast_status_update)

      chat.enqueue_response!(content: "Hello")

      expect(ChatResponseJob).to have_received(:perform_later).with(
        chat.id,
        "Hello",
        [],
        tenant_id: chat.send(:response_job_tenant_id),
      )
      expect(chat.reload).to be_streaming
      expect(chat).to have_received(:broadcast_status_update)
    end

    it "does not transition an already-streaming chat again" do
      chat = create(:chat, :user_context, user: create(:user), agent:)
      chat.streaming!
      allow(chat).to receive(:streaming!)
      allow(chat).to receive(:broadcast_status_update)

      chat.enqueue_response!(content: "Hello again")

      expect(ChatResponseJob).to have_received(:perform_later).with(
        chat.id,
        "Hello again",
        [],
        tenant_id: chat.send(:response_job_tenant_id),
      )
      expect(chat).not_to have_received(:streaming!)
      expect(chat).to have_received(:broadcast_status_update)
    end

    it "normalizes interrupted tool call history before enqueueing a new turn" do
      chat = create(:chat, :user_context, user: create(:user), agent:)
      assistant_message = create(:message, :assistant, chat:, content: "")
      resolved_tool_call = create(:tool_call, message: assistant_message)
      dangling_tool_call = create(:tool_call, message: assistant_message)
      create(:message, :tool, chat:, tool_call_id: resolved_tool_call.id, content: "done")
      allow(chat).to receive(:broadcast_status_update)

      chat.enqueue_response!(content: "Hello again")

      expect(assistant_message.reload.tool_calls.pluck(:id)).to eq([resolved_tool_call.id])
      expect(ToolCall.exists?(dangling_tool_call.id)).to be(false)
    end

    it "restores idle status when job enqueue fails after switching to streaming" do
      chat = create(:chat, :user_context, user: create(:user), agent:)
      allow(chat).to receive(:broadcast_status_update)
      allow(ChatResponseJob).to receive(:perform_later).and_raise(StandardError, "queue offline")

      expect do
        chat.enqueue_response!(content: "Hello")
      end.to raise_error(StandardError, "queue offline")

      expect(chat.reload).to be_idle
      expect(chat).to have_received(:broadcast_status_update).twice
    end

    it "does not reset chats that were already streaming when enqueue fails" do
      chat = create(:chat, :user_context, user: create(:user), agent:, status: :streaming)
      allow(chat).to receive(:broadcast_status_update)
      allow(ChatResponseJob).to receive(:perform_later).and_raise(StandardError, "queue offline")

      expect do
        chat.enqueue_response!(content: "Hello again")
      end.to raise_error(StandardError, "queue offline")

      expect(chat.reload).to be_streaming
      expect(chat).to have_received(:broadcast_status_update).once
    end

    it "raises for unsupported chat contexts" do
      chat = create(:chat, :test_context, user: create(:user), agent:)

      expect do
        chat.enqueue_response!(content: "Hello")
      end.to raise_error("Unsupported chat context 'test' for response dispatch.")
    end

    it "raises recovery errors when resetting the enqueue state fails" do
      chat = create(:chat, :user_context, user: create(:user), agent:)
      allow(chat).to receive(:broadcast_status_update).and_raise(StandardError, "broadcast failed")

      expect { chat.send(:recover_from_enqueue_failure, true) }.to raise_error(StandardError, "broadcast failed")
      expect(chat.reload).to be_idle
    end
  end

  describe "#stop_stream!" do
    let(:user) { create(:user) }
    let(:parent_chat) { create(:chat, :user_context, :streaming, user:) }
    let(:streaming_child) { create(:chat, :streaming, parent_chat:, user:) }
    let(:idle_child) { create(:chat, parent_chat:, user:) }
    let(:streaming_grandchild) { create(:chat, :streaming, parent_chat: streaming_child, user:) }

    def expect_cancelled_status_broadcast(chat, parent_chat_id: nil)
      expected_payload = {
        type: "status",
        chat_id: chat.id,
        status: "cancelled",
        parent_chat_id:,
      }.compact

      expect(ActionCable.server).to have_received(:broadcast).with(
        parent_chat.ui_stream_channel_name,
        hash_including(expected_payload),
      )
    end

    before do
      streaming_child
      idle_child
      streaming_grandchild
      allow(ActionCable.server).to receive(:broadcast)
      parent_chat.stop_stream!
    end

    it "cancels the root chat and only the active descendant streams" do
      expect(parent_chat.reload).to be_cancelled
      expect(streaming_child.reload).to be_cancelled
      expect(streaming_grandchild.reload).to be_cancelled
      expect(idle_child.reload).to be_idle
    end

    it "broadcasts cancelled status for the root and active descendant streams" do
      expect_cancelled_status_broadcast(parent_chat)
      expect_cancelled_status_broadcast(streaming_child, parent_chat_id: parent_chat.id)
      expect_cancelled_status_broadcast(streaming_grandchild, parent_chat_id: streaming_child.id)
    end

    it "removes dangling tool calls from interrupted assistant frames" do
      assistant_message = create(:message, :assistant, chat: parent_chat, content: "")
      completed_tool_call = create(:tool_call, message: assistant_message)
      dangling_tool_call = create(:tool_call, message: assistant_message)
      create(:message, :tool, chat: parent_chat, tool_call_id: completed_tool_call.id, content: "done")

      parent_chat.stop_stream!

      expect(assistant_message.reload.tool_calls.pluck(:id)).to eq([completed_tool_call.id])
      expect(ToolCall.exists?(dangling_tool_call.id)).to be(false)
    end

    it "deletes blank interrupted assistant frames when every tool call was dangling" do
      assistant_message = create(:message, :assistant, chat: parent_chat, content: "")
      create(:tool_call, message: assistant_message)

      parent_chat.stop_stream!

      expect(Message.exists?(assistant_message.id)).to be(false)
    end

    it "deletes orphan assistant frames with no content and no tool calls before a new turn" do
      assistant_message = create(:message, :assistant, chat: parent_chat, content: nil, thinking_text: nil)

      expect do
        parent_chat.enqueue_response!(content: "Retry")
      end.to have_enqueued_job(ChatResponseJob)

      expect(Message.exists?(assistant_message.id)).to be(false)
    end

    it "keeps interrupted assistant frames with visible content after removing dangling tool calls" do
      assistant_message = create(:message, :assistant, chat: parent_chat, content: "Partial reply")
      tool_call = create(:tool_call, message: assistant_message)

      parent_chat.stop_stream!

      expect(ToolCall.exists?(tool_call.id)).to be(false)
      expect(Message.exists?(assistant_message.id)).to be(true)
    end

    it "keeps interrupted assistant frames with thinking text after removing dangling tool calls" do
      assistant_message = create(:message, :assistant, chat: parent_chat, content: "", thinking_text: "Thinking")
      tool_call = create(:tool_call, message: assistant_message)

      parent_chat.stop_stream!

      expect(ToolCall.exists?(tool_call.id)).to be(false)
      expect(Message.exists?(assistant_message.id)).to be(true)
    end

    it "keeps persistent widget tool calls that intentionally pause without tool result messages" do
      assistant_message = create(:message, :assistant, chat: parent_chat, content: "")
      state = Capabilities::HumanInTheLoop::ToolCallState.build(
        prompt_text: "Need a clarification.",
        raw_questions: [{ prompt: "Which color?", options: ["Red", "Blue"] }],
        capability: build(:capabilities_human_in_the_loop_standalone),
      )
      tool_call = create(
        :tool_call,
        message: assistant_message,
        name: "ask_user_questions",
        arguments: state.to_h,
      )

      parent_chat.stop_stream!

      expect(ToolCall.exists?(tool_call.id)).to be(true)
      expect(Message.exists?(assistant_message.id)).to be(true)
    end
  end

  describe "#persistent_widget_tool_call?" do
    let(:subject_chat) { build(:chat) }

    it "returns false when the tool call does not expose widget rendering" do
      expect(subject_chat.send(:persistent_widget_tool_call?, Object.new)).to be(false)
    end

    it "returns false when widget rendering lookup raises" do
      tool_call = Object.new

      def tool_call.tool_call_widget_render_config
        raise "boom"
      end

      expect(subject_chat.send(:persistent_widget_tool_call?, tool_call)).to be(false)
    end
  end

  describe "tenant resolution helpers" do
    it "returns nil for blank chats when resolving a tenant id" do
      expect(build(:chat).send(:tenant_id_for_chat, nil)).to be_nil
    end

    it "resolves the tenant id from an agent-backed chat" do
      tenant = create(:tenant)
      agent = build(:agent, operation: create(:operation, tenant:))
      agent_chat = build(:chat, user: nil, agent:)

      expect(agent_chat.send(:tenant_id_for_chat, agent_chat)).to eq(tenant.id)
    end

    it "returns nil for blank operation owners" do
      expect(build(:chat).send(:tenant_id_for_operation_owner, nil)).to be_nil
    end

    it "returns nil when an operation owner has no operation" do
      owner_without_operation = instance_double(Agent, operation: nil)

      expect(build(:chat).send(:tenant_id_for_operation_owner, owner_without_operation)).to be_nil
    end
  end

  describe "stale tool-result compaction" do
    let(:chat) { create(:chat) }

    it "returns an empty stale set before to_llm is called" do
      expect(chat.stale_message_ids).to eq(Set.new)
    end

    it "exposes the instance variable set by to_llm for Message#to_llm to consult" do
      chat.instance_variable_set(:@stale_message_ids, Set.new([1, 2, 3]))
      expect(chat.stale_message_ids).to eq(Set.new([1, 2, 3]))
    end
  end
end
