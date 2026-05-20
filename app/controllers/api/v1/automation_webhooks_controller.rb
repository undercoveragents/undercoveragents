# frozen_string_literal: true

module Api
  module V1
    class AutomationWebhooksController < Api::BaseController
      skip_before_action :require_api_authentication

      before_action :set_automation_trigger
      before_action :authenticate_automation_trigger!

      rescue_from AutomationTriggers::Dispatcher::InvalidPayload, with: :render_invalid_payload

      def create
        result_record = AutomationTriggers::Dispatcher.new(
          automation_trigger: @automation_trigger,
          payload: webhook_payload,
          source: :webhook,
        ).call

        render json: webhook_response(result_record), status: :accepted
      end

      private

      def set_automation_trigger
        @automation_trigger = AutomationTrigger.includes(:schedulable).find(params.expect(:id))
        return if @automation_trigger.trigger_webhook? && @automation_trigger.enabled?

        render_not_found("Automation webhook not found")
        nil
      rescue ActiveRecord::RecordNotFound
        render_not_found("Automation webhook not found")
        nil
      end

      def authenticate_automation_trigger!
        return if performed?
        return if @automation_trigger.webhook_secret_valid?(webhook_secret)

        render json: { error: "Unauthorized", message: "Invalid or missing webhook secret" }, status: :unauthorized
      end

      def webhook_secret
        request.headers[AutomationTrigger::WEBHOOK_SECRET_HEADER].to_s.strip.presence ||
          extract_bearer_token.presence ||
          params[:secret].presence
      end

      def webhook_payload
        if request.media_type == Mime[:json].to_s
          raw_body = request.raw_post.to_s
          return {} if raw_body.blank?

          parsed = JSON.parse(raw_body)
          raise invalid_payload("Webhook payload must be a JSON object") unless parsed.is_a?(Hash)

          parsed
        else
          params.to_unsafe_h.except("controller", "action", "id", "secret")
        end
      rescue JSON::ParserError
        raise invalid_payload("Webhook payload must be valid JSON")
      end

      def webhook_response(result_record)
        target = @automation_trigger.schedulable
        target_payload = {
          type: target.class.model_name.element,
          id: target.id,
          name: target.name,
        }

        {
          invocation_id: result_record.id,
          invocation_type: result_record.class.model_name.element,
          status: result_record.status,
          schedulable: target_payload,
          target.class.model_name.element.to_sym => target_payload.except(:type),
          trigger: {
            id: @automation_trigger.id,
            name: @automation_trigger.name,
            type: @automation_trigger.trigger_type,
          },
        }
      end

      def invalid_payload(message)
        AutomationTriggers::Dispatcher::InvalidPayload.new(message)
      end

      def render_invalid_payload(error)
        render_unprocessable(error.message)
      end
    end
  end
end
