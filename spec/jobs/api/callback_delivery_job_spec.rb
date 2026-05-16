# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::CallbackDeliveryJob do
  let(:token_data) { ApiClient.generate_token }
  let(:tenant) { create(:tenant) }
  let(:operation) { create(:operation, tenant:) }
  let(:api_client) do
    create(:api_client, tenant:, token_prefix: token_data[:prefix], token_digest: token_data[:digest])
  end
  let(:mission) { create(:mission, operation:) }
  let(:run) do
    create(:mission_run,
           mission:,
           api_client:,
           callback_url: "https://example.com/webhook",
           status: "completed",
           started_at: 2.minutes.ago,
           completed_at: 1.minute.ago,
           variables: { "result" => "data", "_output_meta" => { "status" => "success" } },)
  end

  describe "#perform" do
    it "delivers the callback via HTTP POST" do
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 200)

      described_class.perform_now(run.id, tenant_id: mission.operation.tenant_id)

      expect(WebMock).to(have_requested(:post, "https://example.com/webhook")
        .with do |req|
          body = JSON.parse(req.body)
          body["event"] == "mission_run.completed" &&
            body["run_id"] == run.id &&
            body["status"] == "completed" &&
            body["result"]["output"]["result"] == "data"
        end)
    end

    it "supports callback delivery without tenant scope for backward compatibility" do
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 200)

      described_class.perform_now(run.id)

      expect(WebMock).to have_requested(:post, "https://example.com/webhook")
    end

    it "includes HMAC signature in headers" do
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 200)

      described_class.perform_now(run.id, tenant_id: mission.operation.tenant_id)

      expect(WebMock).to(have_requested(:post, "https://example.com/webhook")
        .with do |req|
          req.headers["X-Signature-Sha256"].present?
        end)
    end

    it "attempts delivery on non-success response" do
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 500, body: "Internal Server Error")

      # retry_on catches the error in perform_now; verify the request was attempted
      described_class.perform_now(run.id, tenant_id: mission.operation.tenant_id)

      expect(WebMock).to have_requested(:post, "https://example.com/webhook")
    end

    it "raises a concise error when a failed callback has no body" do
      response = instance_double(Net::HTTPInternalServerError, code: "500", body: nil)
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(Net::HTTP).to receive(:post).and_return(response)

      expect do
        described_class.new.perform(run.id, tenant_id: mission.operation.tenant_id)
      end.to raise_error(RuntimeError, "Callback delivery failed: HTTP 500 — ")
    end

    it "skips delivery when callback_url is blank" do
      run.update!(callback_url: nil)

      expect { described_class.perform_now(run.id, tenant_id: mission.operation.tenant_id) }.not_to raise_error
      expect(WebMock).not_to have_requested(:post, "https://example.com/webhook")
    end

    it "discards when run is not found" do
      expect { described_class.perform_now(999_999, tenant_id: create(:tenant).id) }.not_to raise_error
    end

    it "delivers without signature when api_client is nil" do
      run.update!(api_client: nil)
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 200)

      described_class.perform_now(run.id, tenant_id: mission.operation.tenant_id)

      expect(WebMock).to have_requested(:post, "https://example.com/webhook")
        .with(headers: { "X-Signature-Sha256" => "" })
    end

    it "does not deliver a callback for a run outside the provided tenant" do
      foreign_tenant = create(:tenant)
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 200)

      described_class.perform_now(run.id, tenant_id: foreign_tenant.id)

      expect(WebMock).not_to have_requested(:post, "https://example.com/webhook")
    end

    it "handles run with nil timestamps and variables" do
      pending_run = create(:mission_run,
                           mission:,
                           api_client:,
                           callback_url: "https://example.com/webhook",
                           status: "pending",
                           variables: {},)
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 200)

      described_class.perform_now(pending_run.id, tenant_id: mission.operation.tenant_id)

      expect(WebMock).to have_requested(:post, "https://example.com/webhook")
    end
  end
end
