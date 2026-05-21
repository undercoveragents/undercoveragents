# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::AgentAlphaMessages", :unauthenticated do
  let(:user) { create(:user, :admin, tenant: default_tenant) }
  let!(:configured_preference) { create(:system_preference, :configured, tenant: user.tenant) }
  let(:agent_alpha) { BuiltinAgents::Resolver.find!("agent_alpha", tenant: user.tenant) }
  let!(:model_record) do
    create(
      :model,
      model_id: configured_preference.model_id,
      provider: configured_preference.llm_connector.provider,
    )
  end
  let!(:chat) do
    create(
      :chat,
      :application_context,
      user:,
      agent: agent_alpha,
      model: model_record,
      title: "#{agent_alpha.name} — Existing",
    )
  end
  let(:source_user_message) { create(:message, :user, chat:, content: "Retry this Agent Alpha request") }
  let!(:assistant_message) do
    source_user_message
    create(:message, :assistant, chat:, content: "Initial Agent Alpha response")
  end

  before do
    sign_in(user)
  end

  def page_context_token_for(path)
    get path

    document = response.parsed_body
    document.at_css("#admin-agent-alpha-page-context")&.[]("data-page-context-token")
  end

  def expect_verified_page_context(token, mission)
    verified_context = AgentAlpha::PageContext.verify(token, user:, tenant: user.tenant)

    expect(verified_context).to include(
      "current_object" => hash_including(
        "type" => "Mission",
        "label" => mission.name,
      ),
      "page" => hash_including(
        "controller" => "admin/missions",
        "action" => "designer",
      ),
      "reference_trigger" => "#",
    )
  end

  def expect_enqueued_runtime_context_for(mission)
    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
    serialized_mission = ActiveJob::Arguments.serialize([mission]).first

    expect(enqueued[:args][3]).to include(
      "ui_context" => hash_including(
        "current_object" => hash_including("label" => mission.name),
        "operation" => hash_including("name" => user.tenant.default_operation.name),
      ),
      "mission" => serialized_mission,
    )
  end

  def reference_payload_for(record, kind:, mention: nil, source: "context")
    [
      {
        kind:,
        id: record.id,
        label: record.name,
        mention:,
        source:,
      }.compact,
    ].to_json
  end

  def expect_enqueued_reference_payload_for(mission)
    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
    message_payload = ChatReferences::MessagePayload.parse(enqueued[:args][1])

    expect(enqueued[:args][0]).to eq(chat.id)
    expect(message_payload.display_content).to eq("Update #launch-plan with better output")
    expect(message_payload.prompt_content).to eq(
      expected_reference_prompt(
        "Update mission id: #{mission.id} with better output",
        mission,
        label: "#launch-plan",
      ),
    )
  end

  def expect_enqueued_context_reference_prompt_for(mission)
    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
    message_payload = ChatReferences::MessagePayload.parse(enqueued[:args][1])

    expect(message_payload.prompt_content).to eq(expected_reference_prompt("Use the selected context", mission))
  end

  def expected_reference_prompt(content, mission, label: mission.name)
    "#{content}\nReferenced records:\n- #{expected_reference_prompt_mapping(mission, label:)}"
  end

  def expected_reference_prompt_mapping(mission, label: mission.name)
    "#{label} => Mission: #{mission.name} | id: #{mission.id} | slug: #{mission.slug}"
  end

  describe "POST /admin/agent_alpha/messages" do
    it "enqueues a chat response job for the persistent application chat" do
      expect do
        post admin_agent_alpha_messages_path, params: { message: { content: "Hello", chat_id: chat.id } }
      end.to have_enqueued_job(ChatResponseJob).with(
        chat.id,
        "Hello",
        [],
        tenant_id: chat.send(:response_job_tenant_id),
      )
    end

    it "expands selected inline references before enqueueing the prompt" do
      mission = create(:mission, operation: user.tenant.default_operation, name: "Launch Plan")
      references = reference_payload_for(mission, kind: "missions", mention: "#launch-plan", source: "inline")

      expect do
        post admin_agent_alpha_messages_path, params: {
          message: { content: "Update #launch-plan with better output", chat_id: chat.id, references: },
        }
      end.to have_enqueued_job(ChatResponseJob).with(
        chat.id,
        a_string_including("chat_references"),
        [],
        hash_including(
          "ui_context" => hash_including(
            "references" => [hash_including("id" => mission.id, "mention" => "#launch-plan")],
          ),
        ),
        tenant_id: chat.send(:response_job_tenant_id),
      )

      expect_enqueued_reference_payload_for(mission)
    end

    it "verifies the current admin page context and passes it to the job" do
      user.tenant.ensure_core_resources!
      mission = create(:mission, operation: user.tenant.default_operation)
      token = page_context_token_for(designer_admin_mission_path(mission))
      expect_verified_page_context(token, mission)

      post admin_agent_alpha_messages_path, params: {
        message: {
          content: "Hello",
          chat_id: chat.id,
          ui_context_token: token,
        },
      }

      expect_enqueued_runtime_context_for(mission)
    end

    it "passes selected context references through the Agent Alpha UI context" do
      mission = create(:mission, operation: user.tenant.default_operation, name: "Launch Plan")
      references = reference_payload_for(mission, kind: "missions")

      post admin_agent_alpha_messages_path, params: {
        message: { content: "Use the selected context", chat_id: chat.id, references: },
      }

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      expect(enqueued[:args][3]).to include(
        "ui_context" => hash_including(
          "references" => [
            hash_including(
              "kind" => "missions",
              "type" => "Mission",
              "id" => mission.id,
              "label" => mission.name,
              "slug" => mission.slug,
            ),
          ],
        ),
      )
      expect_enqueued_context_reference_prompt_for(mission)
    end

    it "returns ok" do
      post admin_agent_alpha_messages_path, params: { message: { content: "Hello", chat_id: chat.id } }

      expect(response).to have_http_status(:ok)
    end

    it "returns a turbo-stream status update on turbo requests" do
      post admin_agent_alpha_messages_path,
           params: { message: { content: "Hello", chat_id: chat.id } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(chat.reload).to be_streaming
      expect(response.body).to include("chat-#{chat.id}-status")
    end

    it "keeps an already-streaming application chat streaming" do
      chat.streaming!

      post admin_agent_alpha_messages_path,
           params: { message: { content: "Hello again", chat_id: chat.id } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(chat.reload).to be_streaming
    end

    it "rejects a chat for the current user outside the application context" do
      other_context_chat = create(:chat, :playground_context, user:, agent: chat.agent)

      post admin_agent_alpha_messages_path,
           params: { message: { content: "Hello", chat_id: other_context_chat.id } }

      expect(response).to have_http_status(:not_found)
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
        model_record.update!(modalities: { "input" => ["text", "file"], "output" => ["text"] })
      end

      it "uploads attachments and passes signed_ids to the job" do
        expect do
          post admin_agent_alpha_messages_path, params: {
            message: { content: "Check this file", chat_id: chat.id, attachments: [file] },
          }
        end.to change(ActiveStorage::Blob, :count).by(1)
           .and have_enqueued_job(ChatResponseJob)
      end

      it "enqueues the job with attachment signed_ids" do
        post admin_agent_alpha_messages_path, params: {
          message: { content: "Check this file", chat_id: chat.id, attachments: [file] },
        }

        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        args = enqueued[:args]
        expect(args[0]).to eq(chat.id)
        expect(args[1]).to eq("Check this file")
        expect(args[2]).to be_an(Array)
        expect(args[2].length).to eq(1)
      end
    end

    it "rejects another application chat id that does not belong to the current user" do
      other_user_chat = create(
        :chat,
        :application_context,
        user: create(:user, :admin),
        agent: chat.agent,
      )

      post admin_agent_alpha_messages_path, params: { message: { content: "Hello", chat_id: other_user_chat.id } }

      expect(response).to have_http_status(:not_found)
    end

    it "returns unprocessable content when the default LLM is not configured" do
      SystemPreference.where(tenant: user.tenant).delete_all

      expect do
        post admin_agent_alpha_messages_path, params: { message: { content: "Hello", chat_id: chat.id } }
      end.not_to have_enqueued_job(ChatResponseJob)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /admin/agent_alpha/messages/:message_id/feedback" do
    it "stores assistant feedback" do
      expect do
        post message_feedback_admin_agent_alpha_path(message_id: assistant_message.id),
             params: { feedback: { value: "positive" } }
      end.to change(MessageFeedback, :count).by(1)

      feedback = MessageFeedback.last
      expect(response).to have_http_status(:no_content)
      expect(feedback).to have_attributes(
        message: assistant_message,
        chat:,
        user:,
        value: "positive",
      )
    end

    it "returns validation errors for invalid feedback" do
      post message_feedback_admin_agent_alpha_path(message_id: assistant_message.id),
           params: { feedback: { value: "negative", category: "bogus" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to include("Category is not included in the list")
    end
  end
end
