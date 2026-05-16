# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Messages" do
  let(:user) { User.find_by(role: "admin") }
  let(:tenant) { user.tenant.tap(&:ensure_core_resources!) }
  let!(:agent) { create(:agent, enabled: true, operation: tenant.default_operation) }
  let!(:client_channel) { create_client_channel(agent:) }
  let(:chat) { create_channel_chat(user:, agent:, channel: client_channel) }

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
end
