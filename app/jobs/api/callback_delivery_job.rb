# frozen_string_literal: true

module Api
  class CallbackDeliveryJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 3
    discard_on ActiveRecord::RecordNotFound

    def perform(run_id, tenant_id: nil)
      run = find_run(run_id, tenant_id:)
      return unless run

      return if run.callback_url.blank?

      payload = build_payload(run)
      signature = sign_payload(payload, run.api_client)

      uri = URI.parse(run.callback_url)
      response = Net::HTTP.post(
        uri,
        payload,
        "Content-Type" => "application/json",
        "X-Signature-SHA256" => signature,
        "User-Agent" => "UndercoverAgents-Webhook/1.0",
      )

      return if response.is_a?(Net::HTTPSuccess)

      raise "Callback delivery failed: HTTP #{response.code} — #{response.body&.truncate(200)}"
    end

    private

    def find_run(run_id, tenant_id: nil)
      scope = MissionRun
      return scope.find_by(id: run_id) if tenant_id.blank?

      scope.joins(mission: :operation).find_by(id: run_id, operations: { tenant_id: })
    end

    def build_payload(run)
      variables = run.variables || {}
      output_meta = variables["_output_meta"]

      {
        event: "mission_run.completed",
        run_id: run.id,
        mission_id: run.mission_id,
        status: run.status,
        result: {
          output: variables.except("_trigger_data", "_current_node_data", "_nesting_depth", "_output_meta"),
          meta: output_meta,
        },
        error: run.error,
        started_at: run.started_at&.iso8601,
        completed_at: run.completed_at&.iso8601,
        duration: run.duration&.round(2),
      }.to_json
    end

    def sign_payload(payload, api_client)
      return "" unless api_client

      OpenSSL::HMAC.hexdigest("SHA256", api_client.token_digest, payload)
    end
  end
end
