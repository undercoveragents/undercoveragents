# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Messages" do
  let(:user) { User.find_by(role: "admin") }
  let(:tenant) { user.tenant.tap(&:ensure_core_resources!) }
  let!(:agent) { create(:agent, enabled: true, operation: tenant.default_operation) }
  let!(:client_channel) { create_client_channel(agent:) }
  let(:chat) { create_channel_chat(user:, agent:, channel: client_channel) }
  let!(:assistant_message) { create(:message, :assistant, chat:, content: "Initial response") }

  def create_client_channel(agent:, default: true, name: "Support Channel")
    create(:channel, :client, tenant:, name:, default:).tap do |channel|
      create(:channel_target, channel:, target: agent, default: true)
    end
  end

  def create_channel_chat(user:, agent:, channel:)
    create(
      :chat,
      :user_context,
      user:,
      agent:,
      channel:,
      channel_target: channel.default_target,
    )
  end

  before do
    tenant
  end

  describe "POST /chat/:chat_id/messages" do
    it "enqueues a ChatResponseJob and returns ok" do
      expect { post chat_messages_path(chat), params: { message: { content: "Hello" } } }
        .to have_enqueued_job(ChatResponseJob)
      expect(response).to have_http_status(:ok)
    end

    it "passes selected thinking effort when the client channel enables the selector" do
      client_channel.update!(
        configuration: client_channel.configuration.merge("thinking_level_selector_enabled" => true),
      )
      allow(ChatResponseJob).to receive(:perform_later)

      post chat_messages_path(chat), params: { message: { content: "Hello", thinking_effort: "low" } }

      expect(ChatResponseJob).to have_received(:perform_later).with(
        chat.id,
        "Hello",
        [],
        { "llm_config" => { "thinking_effort" => "low" } },
        tenant_id: tenant.id,
      )
    end

    it "sends model-default thinking when the enabled selector is left blank" do
      client_channel.update!(
        configuration: client_channel.configuration.merge("thinking_level_selector_enabled" => true),
      )
      allow(ChatResponseJob).to receive(:perform_later)

      post chat_messages_path(chat), params: { message: { content: "Hello", thinking_effort: "" } }

      expect(ChatResponseJob).to have_received(:perform_later).with(
        chat.id,
        "Hello",
        [],
        { "llm_config" => { "thinking_effort" => nil } },
        tenant_id: tenant.id,
      )
    end

    it "ignores posted thinking effort when the client channel hides the selector" do
      allow(ChatResponseJob).to receive(:perform_later)

      post chat_messages_path(chat), params: { message: { content: "Hello", thinking_effort: "high" } }

      expect(ChatResponseJob).to have_received(:perform_later).with(chat.id, "Hello", [], tenant_id: tenant.id)
    end

    it "returns not found for another user's chat" do
      other_user = create(:user, tenant:)
      other_chat = create_channel_chat(user: other_user, agent:, channel: client_channel)

      post chat_messages_path(other_chat), params: { message: { content: "Hello" } }

      expect(response).to have_http_status(:not_found)
    end

    it "returns not found for another channel's chat" do
      other_agent = create(:agent, operation: tenant.default_operation, enabled: true)
      other_channel = create_client_channel(agent: other_agent, default: false, name: "Other Channel")
      other_chat = create_channel_chat(user:, agent: other_agent, channel: other_channel)

      post chat_messages_path(other_chat), params: { message: { content: "Hello" } }

      expect(response).to have_http_status(:not_found)
    end

    it "returns a turbo-stream status update on turbo requests" do
      post chat_messages_path(chat),
           params: { message: { content: "Hello" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(chat.reload).to be_streaming
      expect(response.body).to include("chat-#{chat.id}-status")
    end

    it "keeps an already-streaming chat streaming" do
      chat.streaming!

      post chat_messages_path(chat),
           params: { message: { content: "Hello again" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(chat.reload).to be_streaming
    end

    it "enqueues a preview message through the shared messages controller" do
      preview_channel = create_client_channel(agent:, name: "Preview Channel")
      preview_chat = create_channel_chat(user:, agent:, channel: preview_channel)

      expect do
        post chat_messages_path(preview_chat, preview_channel_id: preview_channel.to_param, admin_preview: true),
             params: { message: { content: "Hello" } }
      end.to have_enqueued_job(ChatResponseJob)

      expect(response).to have_http_status(:ok)
    end

    context "with file attachments" do
      let(:file) do
        Rack::Test::UploadedFile.new(
          StringIO.new("test content"),
          "text/plain",
          true,
          original_filename: "test.txt",
        )
      end

      before do
        chat.model.update!(modalities: { "input" => ["text", "file"], "output" => ["text"] })
      end

      it "uploads attachments and passes signed_ids to the job" do
        expect do
          post chat_messages_path(chat), params: {
            message: { content: "Check this file", attachments: [file] },
          }
        end.to change(ActiveStorage::Blob, :count).by(1)
           .and have_enqueued_job(ChatResponseJob)
      end

      it "skips unsupported attachment types" do
        chat.model.update!(modalities: { "input" => ["image"], "output" => ["text"] })

        expect do
          post chat_messages_path(chat), params: {
            message: { content: "Check this file", attachments: [file] },
          }
        end.not_to change(ActiveStorage::Blob, :count)
      end

      it "skips attachments when no model metadata is available" do
        Chat.where(id: chat.id).update_all(model_id: nil) # rubocop:disable Rails/SkipsModelValidations
        allow_any_instance_of(Chat).to receive(:enqueue_response!) # rubocop:disable RSpec/AnyInstance

        expect do
          post chat_messages_path(chat), params: {
            message: { content: "Check this file", attachments: [file] },
          }
        end.not_to change(ActiveStorage::Blob, :count)
      end
    end
  end

  describe "POST /chat/:id/messages/:message_id/feedback" do
    it "stores assistant feedback" do
      expect do
        post message_feedback_chat_path(chat, message_id: assistant_message.id),
             params: { feedback: { value: "negative", category: "incorrect", comment: "Bad answer" } }
      end.to change(MessageFeedback, :count).by(1)

      feedback = MessageFeedback.last
      expect(response).to have_http_status(:no_content)
      expect(feedback).to have_attributes(
        message: assistant_message,
        chat:,
        user:,
        value: "negative",
        category: "incorrect",
        comment: "Bad answer",
      )
    end

    it "updates existing feedback from the same user for the same message" do
      create(:message_feedback, message: assistant_message, chat:, user:)

      expect do
        post message_feedback_chat_path(chat, message_id: assistant_message.id),
             params: { feedback: { value: "positive" } }
      end.not_to change(MessageFeedback, :count)

      feedback = MessageFeedback.last
      expect(response).to have_http_status(:no_content)
      expect(feedback.value).to eq("positive")
      expect(feedback.category).to be_nil
      expect(feedback.comment).to be_nil
    end

    it "returns validation errors for invalid feedback" do
      post message_feedback_chat_path(chat, message_id: assistant_message.id),
           params: { feedback: { value: "negative", category: "bogus" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to include("Category is not included in the list")
    end
  end
end
