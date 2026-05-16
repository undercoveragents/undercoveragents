# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Channel Invocations", :unauthenticated do
  let(:tenant) { create(:tenant, name: "Channel API Tenant") }
  let(:operation) { create(:operation, tenant:, name: "Channel Operation") }

  def auth_headers(raw_token)
    { "Authorization" => "Bearer #{raw_token}" }
  end

  def uploaded_file
    Rack::Test::UploadedFile.new(__FILE__, "text/plain")
  end

  def mission_flow_with_file_input(field_name:, field_type:)
    {
      "nodes" => [
        {
          "id" => "input_1",
          "type" => "input",
          "data" => {
            "fields" => [
              { "variable_name" => "input", "field_type" => "string" },
              { "variable_name" => field_name, "field_type" => field_type, "required" => true },
            ],
          },
        },
      ],
      "edges" => [],
    }
  end

  describe "POST /api/v1/channels/:channel_slug/targets/:target_slug/invocations" do
    context "with a mission target" do
      let(:mission) { create(:mission, operation:, name: "Mission Target") }
      let(:channel) { create(:channel, :api, tenant:, name: "Mission API") }
      let!(:target) { create(:channel_target, channel:, target: mission, default: true) }
      let(:credential) do
        create(:channel_credential, channel:, credential_type: :bearer_token)
      end

      before do
        credential
      end

      it "creates a mission run scoped to the channel target and enqueues execution" do
        json_headers = auth_headers(credential.raw_token).merge("Content-Type" => "application/json")

        expect do
          post api_v1_channel_target_invocations_path(channel_slug: channel.slug, target_slug: target.slug),
               params: { payload: { input: "hello" } }.to_json,
               headers: json_headers
        end.to change(MissionRun, :count).by(1)
                                         .and have_enqueued_job(Api::MissionExecutionJob)

        run = MissionRun.last
        expect(run.channel).to eq(channel)
        expect(run.channel_target).to eq(target)
        expect(response).to have_http_status(:accepted)
        expect(response.parsed_body).to include(
          "invocation_id" => run.id,
          "invocation_type" => "mission_run",
          "status" => "pending",
        )
      end

      it "shows a mission invocation by channel target" do
        run = create(
          :mission_run,
          mission:,
          channel:,
          channel_target: target,
          status: :completed,
          variables: { "answer" => "done" },
        )
        path = api_v1_channel_target_invocation_path(channel_slug: channel.slug, target_slug: target.slug, id: run.id)

        get path, headers: auth_headers(credential.raw_token)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to include(
          "invocation_id" => run.id,
          "invocation_type" => "mission_run",
          "status" => "completed",
        )
        expect(response.parsed_body.dig("result", "output", "answer")).to eq("done")
      end
    end

    context "with an agent target" do
      let(:agent) { create(:agent, operation:, name: "Agent Target") }
      let(:channel) do
        create(:channel, :api, tenant:, name: "Agent API", configuration: { "response_mode" => response_mode })
      end
      let(:response_mode) { "async" }
      let!(:target) { create(:channel_target, channel:, target: agent, default: true) }
      let(:credential) do
        create(:channel_credential, channel:, credential_type: :bearer_token)
      end

      before do
        create(:model, model_id: agent.model_id, provider: "openai")
        credential
      end

      it "creates a channel chat and enqueues the shared chat response job for async mode" do
        path = api_v1_channel_target_invocations_path(channel_slug: channel.slug, target_slug: target.slug)

        expect do
          post path, params: { content: "Hello from API" }, headers: auth_headers(credential.raw_token)
        end.to change(Chat, :count).by(1)
           .and have_enqueued_job(ChatResponseJob)

        chat = Chat.last
        expect(chat.channel).to eq(channel)
        expect(chat.channel_target).to eq(target)
        expect(chat).to be_channel
      end

      it "returns the async invocation payload" do
        path = api_v1_channel_target_invocations_path(channel_slug: channel.slug, target_slug: target.slug)

        post path, params: { content: "Hello from API" }, headers: auth_headers(credential.raw_token)

        expect(response).to have_http_status(:accepted)
        expect(response.parsed_body).to include(
          "invocation_id" => Chat.last.id,
          "invocation_type" => "chat",
          "status" => "streaming",
        )
      end

      context "when the API channel is configured for sync responses" do
        let(:response_mode) { "sync" }
        let(:sync_chat) do
          create(
            :chat,
            :channel_context,
            agent:,
            channel:,
            channel_target: target,
            model: Model.find_by!(model_id: agent.model_id),
          )
        end
        let(:sync_result) { Channels::AgentInvoker::Result.new(chat: sync_chat, response_content: "Pong", sync?: true) }
        let(:invoker) { instance_double(Channels::AgentInvoker, call: sync_result) }

        before do
          allow(Channels::AgentInvoker).to receive(:new).and_return(invoker)
        end

        it "returns the synchronous assistant response" do
          path = api_v1_channel_target_invocations_path(channel_slug: channel.slug, target_slug: target.slug)

          post path, params: { content: "Ping" }, headers: auth_headers(credential.raw_token)

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to include(
            "invocation_type" => "chat",
            "status" => "idle",
          )
          expect(response.parsed_body.dig("result", "content")).to eq("Pong")
        end
      end

      it "shows a chat invocation by channel target" do
        chat = create(:chat, :channel_context, agent:, channel:, channel_target: target, title: "API Chat")
        create(:message, chat:, role: :user, content: "Ping")
        create(:message, chat:, role: :assistant, content: "Pong")
        path = api_v1_channel_target_invocation_path(
          channel_slug: channel.slug,
          target_slug: target.slug,
          id: chat.id,
        )

        get path, headers: auth_headers(credential.raw_token)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to include(
          "invocation_id" => chat.id,
          "invocation_type" => "chat",
          "title" => "API Chat",
        )
        expect(response.parsed_body["messages"].pluck("content")).to eq(["Ping", "Pong"])
      end
    end

    it "rejects invalid or missing channel credentials" do
      channel = create(:channel, :api, tenant:)
      agent = create(:agent, operation:)
      target = create(:channel_target, channel:, target: agent)

      post api_v1_channel_target_invocations_path(channel_slug: channel.slug, target_slug: target.slug),
           params: { content: "Hello" },
           headers: { "Authorization" => "Bearer ch_invalid" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("Unauthorized")
    end

    it "returns not found when the channel slug does not exist" do
      post api_v1_channel_target_invocations_path(channel_slug: "missing", target_slug: "target"),
           params: { content: "Hello" },
           headers: auth_headers("ch_invalid")

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to include("error" => "Not Found", "message" => "Channel not found")
    end

    it "returns not found when the target slug does not exist" do
      channel = create(:channel, :api, tenant:)
      credential = create(:channel_credential, channel:, credential_type: :bearer_token)

      post api_v1_channel_target_invocations_path(channel_slug: channel.slug, target_slug: "missing"),
           params: { content: "Hello" },
           headers: auth_headers(credential.raw_token)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to include("error" => "Not Found", "message" => "Channel target not found")
    end

    it "returns not found when the invocation does not exist" do
      channel = create(:channel, :api, tenant:)
      agent = create(:agent, operation:)
      target = create(:channel_target, channel:, target: agent, default: true)
      credential = create(:channel_credential, channel:, credential_type: :bearer_token)

      get api_v1_channel_target_invocation_path(channel_slug: channel.slug, target_slug: target.slug, id: "999999"),
          headers: auth_headers(credential.raw_token)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to include("error" => "Not Found", "message" => "Invocation not found")
    end

    it "returns failed mission invocation errors" do
      mission = create(:mission, operation:, name: "Failed Mission")
      channel = create(:channel, :api, tenant:, name: "Failure API")
      target = create(:channel_target, :mission, channel:, target: mission, default: true)
      credential = create(:channel_credential, channel:, credential_type: :bearer_token)
      run = create(:mission_run, mission:, channel:, channel_target: target, status: :failed, error: "boom")

      get api_v1_channel_target_invocation_path(channel_slug: channel.slug, target_slug: target.slug, id: run.id),
          headers: auth_headers(credential.raw_token)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["error"]).to eq("boom")
    end

    it "returns unprocessable when required file payload is missing" do
      mission = create(
        :mission,
        operation:,
        name: "Upload Mission",
        flow_data: mission_flow_with_file_input(field_name: "attachment", field_type: "file"),
      )
      channel = create(:channel, :api, tenant:, name: "Upload API")
      target = create(:channel_target, :mission, channel:, target: mission, default: true)
      credential = create(:channel_credential, channel:, credential_type: :bearer_token)

      post api_v1_channel_target_invocations_path(channel_slug: channel.slug, target_slug: target.slug),
           params: { payload: { input: "hello" } },
           headers: auth_headers(credential.raw_token)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include(
        "error" => "Unprocessable Entity",
        "message" => "Missing required fields: attachment",
      )
    end

    it "treats malformed JSON payloads as empty hashes" do
      mission = create(:mission, operation:, name: "Malformed Mission")
      channel = create(:channel, :api, tenant:, name: "Malformed API")
      target = create(:channel_target, :mission, channel:, target: mission, default: true)
      credential = create(:channel_credential, channel:, credential_type: :bearer_token)

      post api_v1_channel_target_invocations_path(channel_slug: channel.slug, target_slug: target.slug),
           params: { payload: "{not-json" },
           headers: auth_headers(credential.raw_token)

      expect(response).to have_http_status(:accepted)
      expect(MissionRun.last.trigger_data).to eq({})
    end

    it "accepts uploaded files passed as a single upload" do
      mission = create(
        :mission,
        operation:,
        name: "Single Upload Mission",
        flow_data: mission_flow_with_file_input(field_name: "attachment", field_type: "file"),
      )
      channel = create(:channel, :api, tenant:, name: "Single Upload API")
      target = create(:channel_target, :mission, channel:, target: mission, default: true)
      credential = create(:channel_credential, channel:, credential_type: :bearer_token)

      post api_v1_channel_target_invocations_path(channel_slug: channel.slug, target_slug: target.slug),
           params: { payload: { input: "hello" }, attachment: uploaded_file },
           headers: auth_headers(credential.raw_token)

      expect(response).to have_http_status(:accepted)
    end

    it "accepts uploaded files passed as arrays" do
      mission = create(
        :mission,
        operation:,
        name: "Array Upload Mission",
        flow_data: mission_flow_with_file_input(field_name: "attachments", field_type: "file_array"),
      )
      channel = create(:channel, :api, tenant:, name: "Array Upload API")
      target = create(:channel_target, :mission, channel:, target: mission, default: true)
      credential = create(:channel_credential, channel:, credential_type: :bearer_token)

      post api_v1_channel_target_invocations_path(channel_slug: channel.slug, target_slug: target.slug),
           params: { payload: { input: "hello" }, attachments: [uploaded_file, uploaded_file] },
           headers: auth_headers(credential.raw_token)

      expect(response).to have_http_status(:accepted)
    end
  end
end
