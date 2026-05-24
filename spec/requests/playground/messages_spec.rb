# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Playground::Messages", :unauthenticated do
  describe "POST /playground/chats/:chat_id/messages" do
    let(:user) { create(:user, :admin, tenant: default_tenant) }
    let(:agent) { create(:agent) }
    let(:chat) { create(:chat, agent:, user:) }
    let!(:assistant_message) { create(:message, :assistant, chat:, content: "Initial response") }

    before do
      create(:model, model_id: "gpt-4.1", provider: "openai")
      sign_in(user)
    end

    def resolved_agent_model
      Model.find_by!(model_id: agent.resolved_model_id)
    end

    it "enqueues the response job" do
      expect do
        post admin_playground_chat_messages_path(chat), params: { message: { content: "Hello" } }
      end.to have_enqueued_job(ChatResponseJob).with(
        chat.id,
        "Hello",
        [],
        tenant_id: chat.send(:response_job_tenant_id),
      )
    end

    it "returns success status" do
      post admin_playground_chat_messages_path(chat), params: { message: { content: "Hello" } }
      expect(response).to have_http_status(:ok)
    end

    it "returns not found for another user's chat" do
      other_chat = create(:chat, agent:, user: create(:user, :admin))

      post admin_playground_chat_messages_path(other_chat), params: { message: { content: "Hello" } }

      expect(response).to have_http_status(:not_found)
    end

    it "returns a turbo-stream status update on turbo requests" do
      post admin_playground_chat_messages_path(chat),
           params: { message: { content: "Hello" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(chat.reload).to be_streaming
      expect(response.body).to include("chat-#{chat.id}-status")
    end

    it "keeps an already-streaming chat streaming" do
      chat.streaming!

      post admin_playground_chat_messages_path(chat),
           params: { message: { content: "Hello again" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(chat.reload).to be_streaming
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
        resolved_agent_model.update!(modalities: { "input" => ["text", "file"], "output" => ["text"] })
      end

      it "uploads attachments and passes signed_ids to the job" do
        expect do
          post admin_playground_chat_messages_path(chat), params: {
            message: { content: "Check this file", attachments: [file] },
          }
        end.to change(ActiveStorage::Blob, :count).by(1)
           .and have_enqueued_job(ChatResponseJob)
      end

      it "enqueues the job with the correct signed_ids" do
        post admin_playground_chat_messages_path(chat), params: {
          message: { content: "Check this file", attachments: [file] },
        }

        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        args = enqueued[:args]
        expect(args[0]).to eq(chat.id)
        expect(args[1]).to eq("Check this file")
        expect(args[2]).to be_an(Array)
        expect(args[2].length).to eq(1)
      end
    end

    describe "POST /admin/playground/chats/:chat_id/messages/:message_id/feedback" do
      it "stores assistant feedback" do
        expect do
          post message_feedback_admin_playground_chat_path(chat, message_id: assistant_message.id),
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
          post message_feedback_admin_playground_chat_path(chat, message_id: assistant_message.id),
               params: { feedback: { value: "negative", category: "other", comment: "Needs work" } }
        end.not_to change(MessageFeedback, :count)

        feedback = MessageFeedback.last
        expect(response).to have_http_status(:no_content)
        expect(feedback.value).to eq("negative")
        expect(feedback.category).to eq("other")
        expect(feedback.comment).to eq("Needs work")
      end

      it "returns validation errors for invalid feedback" do
        post message_feedback_admin_playground_chat_path(chat, message_id: assistant_message.id),
             params: { feedback: { value: "negative", category: "bogus" } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"]).to include("Category is not included in the list")
      end
    end

    context "when the chat agent uses a user-assignable built-in tool" do
      before do
        agent.update!(runtime_tool_keys: ["web.web_search"])
      end

      it "returns success and enqueues the response job" do
        expect do
          post admin_playground_chat_messages_path(chat), params: { message: { content: "Hello" } }
        end.to have_enqueued_job(ChatResponseJob).with(
          chat.id,
          "Hello",
          [],
          tenant_id: chat.send(:response_job_tenant_id),
        )

        expect(response).to have_http_status(:ok)
      end
    end

    context "when the chat agent uses a non-user-assignable built-in tool" do
      before do
        agent.update!(runtime_tool_keys: ["mission_designer.validate_flow"])
      end

      it "returns unprocessable content" do
        post admin_playground_chat_messages_path(chat), params: { message: { content: "Hello" } }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "does not enqueue the response job" do
        expect do
          post admin_playground_chat_messages_path(chat), params: { message: { content: "Hello" } }
        end.not_to have_enqueued_job(ChatResponseJob)
      end
    end
  end
end
