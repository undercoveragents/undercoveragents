# frozen_string_literal: true

module AutomationTriggersHelper
  def automation_trigger_icon(trigger_or_type)
    type = trigger_or_type.respond_to?(:trigger_type) ? trigger_or_type.trigger_type : trigger_or_type.to_s

    case type
    when "schedule"
      "fa-solid fa-clock"
    when "webhook"
      "fa-solid fa-link"
    else
      "fa-solid fa-bolt"
    end
  end

  def automation_trigger_label(trigger_or_type)
    type = trigger_or_type.respond_to?(:trigger_type) ? trigger_or_type.trigger_type : trigger_or_type.to_s

    type == "webhook" ? "Webhook" : "Schedule"
  end

  def automation_trigger_webhook_url(automation_trigger)
    URI.join(request.base_url, api_v1_automation_webhook_path(automation_trigger)).to_s
  end

  def automation_trigger_status_badges(automation_trigger)
    [
      tag.span(automation_trigger_label(automation_trigger), class: "badge badge-neutral"),
      tag.span(
        automation_trigger.enabled? ? "Active" : "Disabled",
        class: automation_trigger.enabled? ? "badge badge-success" : "badge badge-danger",
      ),
    ]
  end

  def automation_trigger_last_activity(automation_trigger)
    return "Never triggered" if automation_trigger.last_triggered_at.blank?

    "Triggered #{time_ago_in_words(automation_trigger.last_triggered_at)} ago"
  end

  def automation_trigger_next_run_label(automation_trigger)
    return "Disabled" unless automation_trigger.enabled?
    return "Not scheduled" if automation_trigger.next_run_at.blank?

    "Next run #{l(automation_trigger.next_run_at, format: :long)}"
  end

  def automation_trigger_schedulable_label(schedulable)
    schedulable.is_a?(RagFlow) ? "RAG Flow" : "Mission"
  end

  def automation_trigger_parent_path(schedulable)
    case schedulable
    when Mission
      designer_admin_mission_path(schedulable)
    when RagFlow
      admin_rag_flow_path(schedulable)
    else
      raise ArgumentError, "Unsupported automation target '#{schedulable.class.name}'."
    end
  end

  def automation_trigger_collection_path(schedulable)
    polymorphic_path([:admin, schedulable, :automation_triggers])
  end

  def automation_trigger_new_path(schedulable, type:)
    new_polymorphic_path([:admin, schedulable, :automation_trigger], type:)
  end

  def automation_trigger_member_path(automation_trigger)
    polymorphic_path([:admin, automation_trigger.schedulable, automation_trigger])
  end

  def automation_trigger_edit_path(automation_trigger)
    edit_polymorphic_path([:admin, automation_trigger.schedulable, automation_trigger])
  end

  def automation_trigger_regenerate_secret_path(automation_trigger)
    helpers = Rails.application.routes.url_helpers

    case automation_trigger.schedulable
    when Mission
      helpers.regenerate_secret_admin_mission_automation_trigger_path(
        automation_trigger.schedulable,
        automation_trigger,
      )
    when RagFlow
      helpers.regenerate_secret_admin_rag_flow_automation_trigger_path(
        automation_trigger.schedulable,
        automation_trigger,
      )
    else
      raise ArgumentError, "Unsupported automation target '#{automation_trigger.schedulable.class.name}'."
    end
  end

  def automation_trigger_last_result_path(automation_trigger)
    case automation_trigger.last_result_record
    when MissionRun
      admin_mission_control_run_path(automation_trigger.last_result_record)
    when RagRun
      admin_rag_flow_run_path(automation_trigger.schedulable, automation_trigger.last_result_record)
    end
  end

  def automation_trigger_edit_actions(automation_trigger:, **)
    actions = [automation_trigger_save_action]
    return actions unless automation_trigger.trigger_webhook?

    actions.unshift(automation_trigger_regenerate_action(automation_trigger))
    actions
  end

  def automation_trigger_save_action
    page_hero_form_action(
      label: "Save Trigger",
      form_id: "automation-trigger-form",
      icon: "fa-solid fa-check",
    )
  end

  def automation_trigger_regenerate_action(automation_trigger)
    policy_page_hero_action(
      automation_trigger,
      :regenerate_secret?,
      label: "Regenerate Secret",
      url: automation_trigger_regenerate_secret_path(automation_trigger),
      icon: "fa-solid fa-rotate",
      style: :secondary,
      method: :post,
      data: {
        controller: "confirm",
        confirm_title_value: "Regenerate Webhook Secret",
        confirm_message_value:
          "Generate a new webhook secret? Existing callers will stop working until they update the secret.",
      },
    )
  end

  def automation_trigger_curl_example(automation_trigger, webhook_secret:)
    url = if automation_trigger.persisted?
            automation_trigger_webhook_url(automation_trigger)
          else
            "https://your-app.example.com/api/v1/automation_webhooks/TRIGGER_ID"
          end

    <<~CURL
      curl -X POST #{url} \\
        -H "Content-Type: application/json" \\
        -H "#{AutomationTrigger::WEBHOOK_SECRET_HEADER}: #{webhook_secret.presence || "<your secret>"}" \\
        -d '{"event":"test"}'
    CURL
  end

  def automation_trigger_schedule_payload_hint(schedulable)
    case schedulable
    when Mission
      "Optional JSON object merged into the mission input every time the schedule fires."
    when RagFlow
      "Optional JSON object stored with each automated RAG run so later tooling can inspect the dispatch context."
    else
      "Optional JSON object included with each automated dispatch."
    end
  end

  def automation_trigger_webhook_payload_hint(schedulable)
    case schedulable
    when Mission
      "Optional JSON object merged with the incoming webhook body. Incoming keys override matching defaults."
    when RagFlow
      "Optional JSON object merged with the incoming webhook body and stored with the triggered RAG run."
    else
      "Optional JSON object merged with the incoming webhook body for each dispatch."
    end
  end
end
