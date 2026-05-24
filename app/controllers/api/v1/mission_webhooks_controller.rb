# frozen_string_literal: true

module Api
  module V1
    class MissionWebhooksController < AutomationWebhooksController
      private

      def authenticate_mission_trigger!
        authenticate_automation_trigger!
      end
    end
  end
end
