# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Mission Webhooks", :unauthenticated do
  let(:tenant) { create(:tenant, name: "Webhook Tenant") }
  let(:operation) { create(:operation, tenant:, name: "Webhook Operation") }
  let(:mission) do
    create(
      :mission,
      operation:,
      flow_data: {
        "nodes" => [
          {
            "id" => "input_1",
            "type" => "input",
            "data" => {
              "fields" => [
                { "variable_name" => "event", "field_type" => "string", "required" => true },
                { "variable_name" => "source", "field_type" => "string" },
              ],
            },
          },
        ],
        "edges" => [],
      },
    )
  end
  let(:mission_trigger) do
    create(
      :mission_trigger,
      :webhook,
      mission:,
      payload: { source: "stripe" },
      name: "Stripe inbound",
    )
  end

  describe "POST /api/v1/mission_webhooks/:id" do
    it "accepts a valid webhook secret and creates a mission run" do
      expect do
        post api_v1_mission_webhook_path(mission_trigger),
             params: { event: "invoice.created" }.to_json,
             headers: {
               "Content-Type" => "application/json",
               MissionTrigger::WEBHOOK_SECRET_HEADER => mission_trigger.raw_webhook_secret,
             }
      end.to change(MissionRun, :count).by(1)

      run = MissionRun.last
      expect(response).to have_http_status(:accepted)
      expect(run.trigger_data).to eq({ "source" => "stripe", "event" => "invoice.created" })
      expect(run.execution_state.dig("trigger", "source")).to eq("webhook")
      expect(mission_trigger.reload.last_mission_run).to eq(run)
    end

    it "enqueues mission execution for valid webhook requests" do
      post api_v1_mission_webhook_path(mission_trigger),
           params: { event: "invoice.created" }.to_json,
           headers: {
             "Content-Type" => "application/json",
             MissionTrigger::WEBHOOK_SECRET_HEADER => mission_trigger.raw_webhook_secret,
           }

      expect(Api::MissionExecutionJob).to have_been_enqueued.with(kind_of(Integer), tenant_id: tenant.id)
    end

    it "returns unauthorized when the secret is invalid" do
      post api_v1_mission_webhook_path(mission_trigger),
           params: { event: "invoice.created" }.to_json,
           headers: {
             "Content-Type" => "application/json",
             MissionTrigger::WEBHOOK_SECRET_HEADER => "mtw_invalid",
           }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to include("error" => "Unauthorized")
    end

    it "returns unprocessable for non-object JSON bodies" do
      post api_v1_mission_webhook_path(mission_trigger),
           params: "[]",
           headers: {
             "Content-Type" => "application/json",
             MissionTrigger::WEBHOOK_SECRET_HEADER => mission_trigger.raw_webhook_secret,
           }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["message"]).to eq("Webhook payload must be a JSON object")
    end

    it "accepts non-JSON payloads and secret params" do
      post api_v1_mission_webhook_path(mission_trigger), params: {
        secret: mission_trigger.raw_webhook_secret,
        event: "invoice.created",
        extra: "value",
      }

      expect(response).to have_http_status(:accepted)
      expect(MissionRun.last.trigger_data).to eq({ "source" => "stripe", "event" => "invoice.created" })
    end

    it "returns not found for disabled webhook triggers" do
      mission_trigger.update!(enabled: false)

      post api_v1_mission_webhook_path(mission_trigger),
           params: { event: "invoice.created" }.to_json,
           headers: {
             "Content-Type" => "application/json",
             MissionTrigger::WEBHOOK_SECRET_HEADER => mission_trigger.raw_webhook_secret,
           }

      expect(response).to have_http_status(:not_found)
    end

    it "returns not found when the trigger does not exist" do
      post api_v1_mission_webhook_path(999_999),
           params: { event: "invoice.created" }.to_json,
           headers: {
             "Content-Type" => "application/json",
             MissionTrigger::WEBHOOK_SECRET_HEADER => mission_trigger.raw_webhook_secret,
           }

      expect(response).to have_http_status(:not_found)
    end

    it "accepts empty JSON bodies as empty payloads" do
      post api_v1_mission_webhook_path(mission_trigger),
           params: "",
           headers: {
             "Content-Type" => "application/json",
             MissionTrigger::WEBHOOK_SECRET_HEADER => mission_trigger.raw_webhook_secret,
           }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["message"]).to eq("Missing required fields: event")
    end
  end

  describe "controller helpers" do
    it "returns early when authentication already rendered a response" do
      controller = Api::V1::MissionWebhooksController.new
      allow(controller).to receive(:performed?).and_return(true)

      expect(controller.send(:authenticate_mission_trigger!)).to be_nil
    end

    it "raises an invalid payload error for malformed JSON bodies" do
      controller = Api::V1::MissionWebhooksController.new
      request = instance_double(ActionDispatch::Request, media_type: Mime[:json].to_s, raw_post: "{")
      allow(controller).to receive_messages(
        request:,
        params: ActionController::Parameters.new,
      )

      expect do
        controller.send(:webhook_payload)
      end.to raise_error(MissionTriggers::Dispatcher::InvalidPayload, "Webhook payload must be valid JSON")
    end
  end
end
