# frozen_string_literal: true

module MissionTriggersHelper
  include AutomationTriggersHelper

  def mission_trigger_icon(trigger_or_type)
    automation_trigger_icon(trigger_or_type)
  end

  def mission_trigger_label(trigger_or_type)
    automation_trigger_label(trigger_or_type)
  end

  def mission_trigger_webhook_url(mission_trigger)
    URI.join(request.base_url, api_v1_mission_webhook_path(mission_trigger)).to_s
  end

  def mission_trigger_status_badges(mission_trigger)
    automation_trigger_status_badges(mission_trigger)
  end

  def mission_trigger_last_activity(mission_trigger)
    automation_trigger_last_activity(mission_trigger)
  end

  def mission_trigger_next_run_label(mission_trigger)
    automation_trigger_next_run_label(mission_trigger)
  end

  def mission_trigger_edit_actions(mission:, mission_trigger:)
    automation_trigger_edit_actions(schedulable: mission, automation_trigger: mission_trigger)
  end

  def mission_trigger_curl_example(mission_trigger, webhook_secret:)
    url = if mission_trigger.persisted?
            mission_trigger_webhook_url(mission_trigger)
          else
            "https://your-app.example.com/api/v1/mission_webhooks/TRIGGER_ID"
          end

    <<~CURL
      curl -X POST #{url} \\
        -H "Content-Type: application/json" \\
        -H "#{AutomationTrigger::WEBHOOK_SECRET_HEADER}: #{webhook_secret.presence || "<your secret>"}" \\
        -d '{"event":"test"}'
    CURL
  end
end
