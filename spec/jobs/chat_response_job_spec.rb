# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatResponseJob do
  before do
    allow(Rails.logger).to receive(:error)
    allow_any_instance_of(Chat).to receive(:configure_for_agent) # rubocop:disable RSpec/AnyInstance
  end

  describe "#perform" do
    let(:agent) { create(:agent) }
    let(:chat) { create(:chat, :with_agent, :user_context, agent:) }

    it "logs an error and finishes gracefully when the chat has no agent" do
      chat_no_agent = create(:chat, :user_context, agent: nil)

      expect { described_class.new.perform(chat_no_agent.id, "Hello") }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/No agent/)
    end

    it "does not respond to a chat outside the provided tenant" do
      tenant = create(:tenant)
      operation = create(:operation, tenant:)
      tenant_agent = create(:agent, operation:)
      tenant_user = create(:user, tenant:)
      tenant_chat = create(:chat, :with_agent, :user_context, agent: tenant_agent, user: tenant_user)
      foreign_tenant = create(:tenant)

      expect do
        described_class.new.perform(tenant_chat.id, "Hello", [], {}, tenant_id: foreign_tenant.id)
      end.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(/\[ChatResponseJob\].*Couldn't find Chat/)
    end

    it "sets the chat to streaming status during execution" do
      allow_any_instance_of(Chat).to receive(:ask) do |chat_instance, _content, &_block| # rubocop:disable RSpec/AnyInstance
        expect(chat_instance.status).to eq("streaming")
      end

      described_class.new.perform(chat.id, "Hello")
    end

    it "sets the chat to idle status after completion" do
      allow_any_instance_of(Chat).to receive(:ask).and_return(nil) # rubocop:disable RSpec/AnyInstance

      described_class.new.perform(chat.id, "Hello")
      expect(chat.reload.status).to eq("idle")
    end

    it "broadcasts chunks via the chat UI stream" do
      chunk = instance_double(RubyLLM::Chunk, content: "Hello world", thinking: nil, tool_call?: false)
      allow_any_instance_of(Chat).to receive(:ask).and_yield(chunk) # rubocop:disable RSpec/AnyInstance
      allow(ActionCable.server).to receive(:broadcast)

      described_class.new.perform(chat.id, "Hello")

      expect_chunk_broadcast(chat, content: "Hello world", kind: "content")
    end

    it "broadcasts thinking chunks via the chat UI stream" do
      chunk = instance_double(RubyLLM::Chunk, content: nil, thinking: "Working through the answer", tool_call?: false)
      allow_any_instance_of(Chat).to receive(:ask).and_yield(chunk) # rubocop:disable RSpec/AnyInstance
      allow(ActionCable.server).to receive(:broadcast)

      described_class.new.perform(chat.id, "Hello")

      expect_chunk_broadcast(chat, content: "Working through the answer", kind: "thinking")
    end

    it "skips thinking broadcasts for chunks that do not expose thinking" do
      chunk_class = Struct.new(:content) do
        def tool_call?
          false
        end
      end
      chunk = chunk_class.new("Hello world")
      allow_any_instance_of(Chat).to receive(:ask).and_yield(chunk) # rubocop:disable RSpec/AnyInstance
      allow(ActionCable.server).to receive(:broadcast)

      described_class.new.perform(chat.id, "Hello")

      expect_chunk_broadcast(chat, content: "Hello world", kind: "content")
    end

    it "preserves the final assistant message content when streaming completes" do
      first_chunk = instance_double(RubyLLM::Chunk, content: "Hello", thinking: nil, tool_call?: false)
      second_chunk = instance_double(RubyLLM::Chunk, content: " world", thinking: nil, tool_call?: false)

      allow_any_instance_of(Chat).to receive(:ask) do |chat_instance, _content, &block| # rubocop:disable RSpec/AnyInstance
        message = create(:message, chat: chat_instance, role: :assistant, content: "")
        chat_instance.instance_variable_set(:@message, message)
        block&.call(first_chunk)
        block&.call(second_chunk)
        message.update!(content: "Hello world")
      end

      described_class.new.perform(chat.id, "Hello")

      expect(chat.messages.order(:id).last.content).to eq("Hello world")
    end

    it "backfills missing application chunks from the final response content" do
      application_chat = create_application_backfill_chat
      thinking_chunk = instance_double(RubyLLM::Chunk, content: nil, thinking: "Delegating", tool_call?: false)
      response = instance_double(RubyLLM::Message, content: "Parent answer ready")
      allow(ActionCable.server).to receive(:broadcast)

      stub_application_backfill_response(
        application_chat,
        response:,
        final_content: "Parent answer ready",
        chunks: [thinking_chunk],
      )

      described_class.new.perform(application_chat.id, "Hello")

      expect_application_backfill_broadcast(application_chat, content: "Parent answer ready")
    end

    it "removes a synthetic terminal assistant message that only concatenates prior tool-loop assistant content" do
      application_chat = create(:chat, :with_agent, :application_context, agent:, user: create(:user, :admin))

      allow_any_instance_of(Chat).to receive(:ask) do |chat_instance, _content, &_block| # rubocop:disable RSpec/AnyInstance
        create(:message, chat: chat_instance, role: :assistant, content: "Let me inspect the mission.")
        create(:message, chat: chat_instance, role: :tool, content: "Mission details")
        create(:message, chat: chat_instance, role: :assistant, content: "Let me update the node.")
        create(:message, chat: chat_instance, role: :tool, content: "Patch applied")
        create(
          :message,
          chat: chat_instance,
          role: :assistant,
          content: "Let me inspect the mission.Let me update the node.",
        )
      end

      described_class.new.perform(application_chat.id, "Hello")

      expect(application_chat.reload.messages.where(role: :assistant).pluck(:content)).to eq(
        ["Let me inspect the mission.", "Let me update the node."],
      )
    end

    it "persists the final assistant content once when streaming is interrupted" do
      first_chunk = instance_double(RubyLLM::Chunk, content: "Hello", thinking: nil, tool_call?: false)
      second_chunk = instance_double(RubyLLM::Chunk, content: " world", thinking: nil, tool_call?: false)

      allow_any_instance_of(Chat).to receive(:ask) do |chat_instance, _content, &block| # rubocop:disable RSpec/AnyInstance
        message = create(:message, chat: chat_instance, role: :assistant, content: "")
        chat_instance.instance_variable_set(:@message, message)
        block&.call(first_chunk)
        block&.call(second_chunk)
        raise Chat::CancelledError
      end

      described_class.new.perform(chat.id, "Hello")

      expect(chat.messages.order(:id).last.content).to eq("Hello world")
    end

    it "skips broadcasting when chunk content is nil" do
      nil_chunk = instance_double(RubyLLM::Chunk, content: nil, thinking: nil, tool_call?: false)
      allow_any_instance_of(Chat).to receive(:ask).and_yield(nil_chunk) # rubocop:disable RSpec/AnyInstance
      allow(ActionCable.server).to receive(:broadcast)

      described_class.new.perform(chat.id, "Hello")

      expect(ActionCable.server).not_to have_received(:broadcast)
        .with(chat.ui_stream_channel_name, hash_including(type: "chunk"))
    end

    it "handles chat cancellation raised by ask" do
      allow_any_instance_of(Chat).to receive(:ask).and_raise(Chat::CancelledError) # rubocop:disable RSpec/AnyInstance

      described_class.new.perform(chat.id, "Hello")
      expect(chat.reload.status).to eq("idle")
    end

    it "keeps a pre-cancelled chat cancelled and does not restart streaming" do
      chat.cancelled!
      ask_called = false

      allow_any_instance_of(Chat).to receive(:ask) do # rubocop:disable RSpec/AnyInstance
        ask_called = true
      end

      described_class.new.perform(chat.id, "Hello")

      expect(chat.reload.status).to eq("cancelled")
      expect(ask_called).to be(false)
    end

    it "handles cancellation before a chat record is available" do
      job = described_class.new
      allow(Chat).to receive(:find).and_raise(Chat::CancelledError)
      allow(job).to receive(:persist_stream_content)
      allow(job).to receive(:finalize_chat)

      expect { job.perform(123, "Hello") }.not_to raise_error

      expect(job).not_to have_received(:persist_stream_content)
      expect(job).to have_received(:finalize_chat).with(nil)
    end

    it "detects cancellation while streaming" do
      allow_any_instance_of(Chat).to receive(:ask) do |chat_instance, _content, &block| # rubocop:disable RSpec/AnyInstance
        chat_instance.class.where(id: chat_instance.id).update_all(status: "cancelled") # rubocop:disable Rails/SkipsModelValidations
        block&.call(instance_double(RubyLLM::Chunk, content: "chunk", thinking: nil, tool_call?: false))
      end

      described_class.new.perform(chat.id, "Hello")
      expect(chat.reload.status).to eq("cancelled")
    end

    context "when an error occurs" do
      it "handles errors before a chat record is available" do
        job = described_class.new
        error = StandardError.new("lookup failed")
        allow(Chat).to receive(:find).and_raise(error)
        allow(job).to receive(:persist_stream_content)
        allow(job).to receive(:broadcast_error_message)
        allow(job).to receive(:finalize_chat)

        expect { job.perform(123, "Hello") }.not_to raise_error

        expect(job).not_to have_received(:persist_stream_content)
        expect(Rails.logger).to have_received(:error).with(/\[ChatResponseJob\].*lookup failed/)
        expect(job).to have_received(:broadcast_error_message).with(nil, error)
        expect(job).to have_received(:finalize_chat).with(nil)
      end

      it "logs the error with [ChatResponseJob] prefix and sets chat to idle" do
        allow_any_instance_of(Chat).to receive(:ask).and_raise(StandardError, "test error") # rubocop:disable RSpec/AnyInstance

        described_class.new.perform(chat.id, "Hello")
        expect(chat.reload.status).to eq("idle")
        expect(Rails.logger).to have_received(:error).with(/\[ChatResponseJob\].*test error/)
      end

      it "broadcasts an error message to the chat stream" do
        allow_any_instance_of(Chat).to receive(:ask).and_raise(StandardError, "test error") # rubocop:disable RSpec/AnyInstance
        allow(ActionCable.server).to receive(:broadcast)

        described_class.new.perform(chat.id, "Hello")

        expect_error_broadcast(chat, /test error/)
      end
    end

    context "when credential decryption fails" do
      it "broadcasts the descriptive error message to the user" do
        allow_any_instance_of(Chat).to receive(:configure_for_agent) # rubocop:disable RSpec/AnyInstance
          .and_raise(Connectors::LlmProvider::CredentialDecryptionError.new("My Connector"))
        allow(ActionCable.server).to receive(:broadcast)

        described_class.new.perform(chat.id, "Hello")

        expect_error_broadcast(chat, /Cannot decrypt credentials for connector 'My Connector'/)
      end
    end

    context "with attachments" do
      before { allow_any_instance_of(Chat).to receive(:ask).and_return(nil) } # rubocop:disable RSpec/AnyInstance

      it "passes image attachments to chat.ask" do
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("image data"),
          filename: "photo.png",
          content_type: "image/png",
        )

        expect_any_instance_of(Chat).to receive(:ask) # rubocop:disable RSpec/AnyInstance
          .with("Describe this", with: [blob])

        described_class.new.perform(chat.id, "Describe this", [blob.signed_id])
      end

      it "omits with: when no attachments are provided" do
        expect_any_instance_of(Chat).to receive(:ask) # rubocop:disable RSpec/AnyInstance
          .with("Hello")

        described_class.new.perform(chat.id, "Hello", [])
      end
    end

    it "generates a title from the first user message" do
      allow_any_instance_of(Chat).to receive(:ask) do |chat_instance, _content, &_block| # rubocop:disable RSpec/AnyInstance
        create(:message, chat: chat_instance, role: :user, content: "What is the meaning of life?")
      end

      described_class.new.perform(chat.id, "What is the meaning of life?")
      expect(chat.reload.title).to eq("What is the meaning of life?")
    end

    it "asks with prompt-safe references and persists the display payload" do
      allow_any_instance_of(Chat).to receive(:ask) do |chat_instance, content, &_block| # rubocop:disable RSpec/AnyInstance
        expect(content).to eq(
          "Update mission id: 23\nReferenced records:\n" \
          "- #launch-plan => Mission: Launch Plan | id: 23 | slug: launch-plan",
        )
        create(:message, chat: chat_instance, role: :user, content:)
      end

      described_class.new.perform(chat.id, packed_reference_content)

      message = chat.messages.user.last
      expect(message.display_content).to eq("Update #launch-plan")
      expect(message.chat_references).to contain_exactly(
        hash_including("id" => 23, "label" => "Launch Plan", "slug" => "launch-plan"),
      )
      expect(message.chat_references.first.keys).to contain_exactly("kind", "type", "id", "slug", "label", "mention")
      expect(chat.reload.title).to eq("Update #launch-plan")
    end

    it "asks with selected context reference ids" do
      allow_any_instance_of(Chat).to receive(:ask) do |chat_instance, content, &_block| # rubocop:disable RSpec/AnyInstance
        expect(content).to eq(
          "Is it valid?\nReferenced records:\n" \
          "- Launch Plan => Mission: Launch Plan | id: 23 | slug: launch-plan",
        )
        create(:message, chat: chat_instance, role: :user, content:)
      end

      described_class.new.perform(chat.id, packed_context_reference_content)
    end

    it "skips display payload persistence when no user message was written" do
      allow_any_instance_of(Chat).to receive(:ask).and_return(nil) # rubocop:disable RSpec/AnyInstance

      expect { described_class.new.perform(chat.id, packed_reference_content) }.not_to change(Message, :count)
    end

    it "does not overwrite a custom title" do
      chat.update!(title: "My Custom Title")
      allow_any_instance_of(Chat).to receive(:ask).and_return(nil) # rubocop:disable RSpec/AnyInstance

      described_class.new.perform(chat.id, "Hello")
      expect(chat.reload.title).to eq("My Custom Title")
    end

    it "handles nil chats in broadcast_error_message" do
      job = described_class.new

      expect { job.send(:broadcast_error_message, nil, StandardError.new("error")) }.not_to raise_error
    end

    it "handles nil chats in finalize_chat" do
      job = described_class.new

      expect { job.send(:finalize_chat, nil) }.not_to raise_error
    end

    context "when the chat is a playground chat" do
      let(:chat) { create(:chat, :with_agent, :playground_context, agent:) }

      it "rejects agents with built-in tools" do
        agent.update!(runtime_tool_keys: ["mission_designer.validate_flow"])
        allow(ActionCable.server).to receive(:broadcast)

        described_class.new.perform(chat.id, "Hello")

        expect_error_broadcast(chat, /Playground does not support agents with built-in tools/)
      end
    end

    context "when the chat is an application chat" do
      let(:chat) { create(:chat, :with_agent, :application_context, agent:, user: create(:user, :admin)) }
      let(:runtime_context) do
        {
          "ui_context" => {
            "page" => {
              "name" => "Mission details",
              "controller" => "admin/missions",
              "action" => "designer",
              "path" => "/admin/missions/policy-mission/designer",
            },
            "current_object" => {
              "type" => "Mission",
              "label" => "Policy Mission",
              "id" => 42,
            },
            "references" => [],
            "reference_trigger" => "#",
          },
        }
      end

      it "configures the chat like a normal agent chat" do
        allow_any_instance_of(Chat).to receive(:ask).and_return(nil) # rubocop:disable RSpec/AnyInstance
        allow(Chat).to receive(:find).with(chat.id).and_return(chat)
        allow(chat).to receive(:configure_for_agent)

        described_class.new.perform(chat.id, "Hello")

        expect(chat).to have_received(:configure_for_agent).with(agent, runtime_context: {})
      end

      it "passes application UI context into agent configuration" do
        allow_any_instance_of(Chat).to receive(:ask).and_return(nil) # rubocop:disable RSpec/AnyInstance
        allow(Chat).to receive(:find).with(chat.id).and_return(chat)
        allow(chat).to receive(:configure_for_agent)

        described_class.new.perform(chat.id, "Hello", [], runtime_context)

        expect(chat).to have_received(:configure_for_agent).with(agent, runtime_context:)
      end

      it "broadcasts chunks through the user-scoped application UI stream" do
        chunk = instance_double(RubyLLM::Chunk, content: "Hello world", thinking: nil, tool_call?: false)
        allow_any_instance_of(Chat).to receive(:ask).and_yield(chunk) # rubocop:disable RSpec/AnyInstance
        allow(ActionCable.server).to receive(:broadcast)

        described_class.new.perform(chat.id, "Hello")

        expect(ActionCable.server).to have_received(:broadcast).with(
          chat.ui_stream_channel_name,
          hash_including(
            type: "chunk",
            chat_id: chat.id,
            content: "Hello world",
          ),
        )
      end
    end

    context "when the chat is a mission designer chat" do
      let(:mission) { create(:mission) }
      let(:chat) { create(:chat, :system_context, agent:, mission:, user: create(:user, :admin)) }

      before do
        create(:model, model_id: "gpt-4.1", provider: "openai")
        create(:system_preference, :configured)
        allow(BuiltinAgents::Runner).to receive(:configure_chat!)
      end

      it "configures the chat via the mission_designer builtin agent" do
        allow_any_instance_of(Chat).to receive(:ask).and_return(nil) # rubocop:disable RSpec/AnyInstance

        described_class.new.perform(chat.id, "Hello")

        expect(BuiltinAgents::Runner).to have_received(:configure_chat!).with(
          hash_including(
            chat:,
            builtin_key: "mission_designer",
            input_values: {
              mission_name: mission.name,
              mission_description: mission.description.to_s,
            },
            runtime_context: { mission: },
          ),
        )
      end

      it "passes image attachments to chat.ask" do
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("image data"),
          filename: "photo.png",
          content_type: "image/png",
        )

        expect_any_instance_of(Chat).to receive(:ask) # rubocop:disable RSpec/AnyInstance
          .with("Describe this mission", with: [blob])

        described_class.new.perform(chat.id, "Describe this mission", [blob.signed_id])
      end

      it "broadcasts an error message when mission context setup fails" do
        allow(BuiltinAgents::Runner).to receive(:configure_chat!).and_raise("LLM error")
        allow(ActionCable.server).to receive(:broadcast)

        described_class.new.perform(chat.id, "Hello")

        expect_error_broadcast(chat, /LLM error/)
      end

      it "broadcasts an error message when the mission cannot be resolved" do
        allow_any_instance_of(Chat).to receive(:mission).and_return(nil) # rubocop:disable RSpec/AnyInstance
        allow(ActionCable.server).to receive(:broadcast)

        described_class.new.perform(chat.id, "Hello")

        expect_error_broadcast(chat, /Mission designer chat is missing its mission/)
      end
    end

    context "when the chat context is unsupported" do
      let(:chat) { create(:chat, :test_context, agent:, user: create(:user)) }

      it "broadcasts an error message for the unsupported response context" do
        allow(ActionCable.server).to receive(:broadcast)

        described_class.new.perform(chat.id, "Hello")

        expect_error_broadcast(chat, /Unsupported chat context 'test' for response dispatch/)
      end
    end

    def create_application_backfill_chat
      tenant = create(:tenant).tap(&:ensure_core_resources!)

      create(
        :chat,
        :with_agent,
        :application_context,
        agent: create(:agent, operation: tenant.default_operation),
        user: create(:user, tenant:),
      )
    end

    def expect_chunk_broadcast(chat, content:, kind:)
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "chunk", chat_id: chat.id, content:, kind:),
      )
    end

    def expect_error_broadcast(chat, message)
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "error", chat_id: chat.id, message:),
      )
    end

    def stub_application_backfill_response(application_chat, response:, final_content:, chunks:)
      allow_any_instance_of(Chat).to receive(:ask) do |chat_instance, _content, &block| # rubocop:disable RSpec/AnyInstance
        next response unless chat_instance.id == application_chat.id

        message = create(:message, chat: chat_instance, role: :assistant, content: "")
        chat_instance.instance_variable_set(:@message, message)
        chunks.each { |chunk| block&.call(chunk) }
        message.update!(content: final_content)
        response
      end
    end

    def expect_application_backfill_broadcast(application_chat, content:)
      expect(ActionCable.server).to have_received(:broadcast).with(
        application_chat.ui_stream_channel_name,
        hash_including(
          type: "chunk",
          chat_id: application_chat.id,
          content:,
          kind: "content",
        ),
      )
    end

    def packed_reference_content
      ChatReferences::MessagePayload.pack(
        content: "Update #launch-plan",
        references: [reference_payload],
      )
    end

    def packed_context_reference_content
      ChatReferences::MessagePayload.pack(
        content: "Is it valid?",
        references: [reference_payload.except("mention")],
      )
    end

    def reference_payload
      {
        "kind" => "missions",
        "id" => 23,
        "type" => "Mission",
        "label" => "Launch Plan",
        "slug" => "launch-plan",
        "mention" => "#launch-plan",
      }
    end
  end
end
