# frozen_string_literal: true

require "rails_helper"

RSpec.describe AutomationTriggersHelper do
  describe "#automation_trigger_icon" do
    it "returns the correct icons for known and unknown trigger types" do
      expect(helper.automation_trigger_icon("schedule")).to eq("fa-solid fa-clock")
      expect(helper.automation_trigger_icon(build(:automation_trigger, :webhook))).to eq("fa-solid fa-link")
      expect(helper.automation_trigger_icon("custom")).to eq("fa-solid fa-bolt")
    end
  end

  describe "#automation_trigger_label" do
    it "returns a webhook label only for webhook triggers" do
      expect(helper.automation_trigger_label("webhook")).to eq("Webhook")
      expect(helper.automation_trigger_label(build(:automation_trigger, :schedule))).to eq("Schedule")
    end
  end

  describe "#automation_trigger_webhook_url" do
    it "builds an absolute webhook url" do
      trigger = create(:automation_trigger, :webhook)
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, base_url: "https://app.example.com"))

      expect(helper.automation_trigger_webhook_url(trigger))
        .to eq("https://app.example.com/api/v1/automation_webhooks/#{trigger.id}")
    end
  end

  describe "#automation_trigger_status_badges" do
    it "returns label and enabled badges" do
      trigger = build(:automation_trigger, :schedule, enabled: true)

      badges = helper.automation_trigger_status_badges(trigger)

      expect(badges.first).to include("Schedule")
      expect(badges.second).to include("Active")
      expect(badges.second).to include("badge-success")
    end

    it "returns a disabled badge for inactive triggers" do
      trigger = build(:automation_trigger, :schedule, enabled: false)

      expect(helper.automation_trigger_status_badges(trigger).second).to include("Disabled", "badge-danger")
    end
  end

  describe "#automation_trigger_last_activity" do
    it "returns a fallback when the trigger never ran" do
      expect(helper.automation_trigger_last_activity(build(:automation_trigger,
                                                           last_triggered_at: nil,))).to eq("Never triggered")
    end

    it "formats the last activity label" do
      trigger = build(:automation_trigger, last_triggered_at: 2.hours.ago)
      allow(helper).to receive(:time_ago_in_words).with(trigger.last_triggered_at).and_return("about 2 hours")

      expect(helper.automation_trigger_last_activity(trigger)).to eq("Triggered about 2 hours ago")
    end
  end

  describe "#automation_trigger_next_run_label" do
    it "returns the disabled and unscheduled labels before formatting a timestamp" do
      expect(helper.automation_trigger_next_run_label(build(:automation_trigger, enabled: false))).to eq("Disabled")
      expect(helper.automation_trigger_next_run_label(build(:automation_trigger,
                                                            next_run_at: nil,))).to eq("Not scheduled")

      trigger = build(:automation_trigger, next_run_at: Time.find_zone!("UTC").parse("2026-05-20 09:00:00"))
      allow(helper).to receive(:l).with(trigger.next_run_at, format: :long).and_return("May 20, 2026 09:00")

      expect(helper.automation_trigger_next_run_label(trigger)).to eq("Next run May 20, 2026 09:00")
    end
  end

  describe "target-aware paths and labels" do
    it "returns schedulable labels and parent paths" do
      mission = create(:mission)
      rag_flow = create(:rag_flow)

      expect(helper.automation_trigger_schedulable_label(mission)).to eq("Mission")
      expect(helper.automation_trigger_schedulable_label(rag_flow)).to eq("RAG Flow")
      expect(helper.automation_trigger_parent_path(mission)).to eq(designer_admin_mission_path(mission))
      expect(helper.automation_trigger_parent_path(rag_flow)).to eq(admin_rag_flow_path(rag_flow))
    end

    it "returns collection, new, member, and edit paths" do
      mission = create(:mission)
      rag_flow = create(:rag_flow)
      mission_trigger = create(:automation_trigger, :webhook, target: mission)
      rag_trigger = create(:automation_trigger, :webhook, target: rag_flow)

      expect(helper.automation_trigger_collection_path(rag_flow))
        .to eq(admin_rag_flow_automation_triggers_path(rag_flow))
      expect(helper.automation_trigger_new_path(rag_flow, type: "schedule"))
        .to eq(new_admin_rag_flow_automation_trigger_path(rag_flow, type: "schedule"))
      expect(helper.automation_trigger_member_path(mission_trigger))
        .to eq(admin_mission_automation_trigger_path(mission, mission_trigger))
      expect(helper.automation_trigger_edit_path(rag_trigger))
        .to eq(edit_admin_rag_flow_automation_trigger_path(rag_flow, rag_trigger))
    end

    it "returns regenerate-secret and last-result paths" do
      mission = create(:mission)
      rag_flow = create(:rag_flow)
      mission_trigger = create(:automation_trigger, :webhook, target: mission)
      rag_trigger = create(:automation_trigger, :webhook, target: rag_flow)
      mission_run = create(:mission_run, mission:)
      rag_run = create(:rag_run, rag_flow:)
      mission_trigger.update!(last_result_record: mission_run)
      rag_trigger.update!(last_result_record: rag_run)

      expect(helper.automation_trigger_regenerate_secret_path(mission_trigger))
        .to eq(regenerate_secret_admin_mission_automation_trigger_path(mission, mission_trigger))
      expect(helper.automation_trigger_regenerate_secret_path(rag_trigger))
        .to eq(regenerate_secret_admin_rag_flow_automation_trigger_path(rag_flow, rag_trigger))
      expect(helper.automation_trigger_last_result_path(mission_trigger))
        .to eq(admin_mission_control_run_path(mission_run))
      expect(helper.automation_trigger_last_result_path(rag_trigger))
        .to eq(admin_rag_flow_run_path(rag_flow, rag_run))
    end

    it "raises for unsupported targets" do
      unsupported = Object.new
      trigger = build(:automation_trigger, :webhook)
      allow(trigger).to receive(:schedulable).and_return(unsupported)

      expect { helper.automation_trigger_parent_path(unsupported) }
        .to raise_error(ArgumentError, "Unsupported automation target 'Object'.")
      expect { helper.automation_trigger_regenerate_secret_path(trigger) }
        .to raise_error(ArgumentError, "Unsupported automation target 'Object'.")
    end

    it "returns nil from automation_trigger_last_result_path when no result is recorded" do
      trigger = build(:automation_trigger, :webhook)
      allow(trigger).to receive(:last_result_record).and_return(nil)

      expect(helper.automation_trigger_last_result_path(trigger)).to be_nil
    end
  end

  describe "#automation_trigger_edit_actions" do
    before do
      allow(helper).to receive_messages(
        page_hero_form_action: :save_action,
        automation_trigger_regenerate_action: :regenerate_action,
      )
    end

    it "returns only the save action for schedule triggers" do
      expect(helper.automation_trigger_edit_actions(automation_trigger: build(:automation_trigger,
                                                                              :schedule,))).to eq([:save_action])
    end

    it "prepends the regenerate action for webhook triggers" do
      expect(helper.automation_trigger_edit_actions(automation_trigger: build(:automation_trigger, :webhook)))
        .to eq([:regenerate_action, :save_action])
    end
  end

  describe "curl and payload hints" do
    it "renders a persisted webhook trigger curl example with the webhook URL and secret" do
      mission = create(:mission)
      persisted_trigger = create(:automation_trigger, :webhook, target: mission)
      allow(helper).to receive(:automation_trigger_webhook_url)
        .with(persisted_trigger)
        .and_return("https://app.example.com/api/v1/automation_webhooks/#{persisted_trigger.id}")

      result = helper.automation_trigger_curl_example(persisted_trigger, webhook_secret: "atw_secret")

      expect(result).to include(
        "https://app.example.com/api/v1/automation_webhooks/#{persisted_trigger.id}",
      )
      expect(result).to include(%(#{AutomationTrigger::WEBHOOK_SECRET_HEADER}: atw_secret))
    end

    it "renders a placeholder curl example for an unsaved trigger" do
      rag_flow = create(:rag_flow)
      unsaved_trigger = build(:automation_trigger, :webhook, target: rag_flow)

      result = helper.automation_trigger_curl_example(unsaved_trigger, webhook_secret: nil)

      expect(result).to include("https://your-app.example.com/api/v1/automation_webhooks/TRIGGER_ID")
      expect(result).to include("<your secret>")
    end

    it "returns schedule payload hints for missions, rag flows, and fallback" do
      mission = create(:mission)
      rag_flow = create(:rag_flow)

      expect(helper.automation_trigger_schedule_payload_hint(mission)).to include("mission input")
      expect(helper.automation_trigger_schedule_payload_hint(rag_flow)).to include("RAG run")
      expect(helper.automation_trigger_schedule_payload_hint(Object.new)).to include("automated dispatch")
    end

    it "returns webhook payload hints for missions, rag flows, and fallback" do
      mission = create(:mission)
      rag_flow = create(:rag_flow)

      expect(helper.automation_trigger_webhook_payload_hint(mission)).to include("incoming webhook body")
      expect(helper.automation_trigger_webhook_payload_hint(rag_flow)).to include("triggered RAG run")
      expect(helper.automation_trigger_webhook_payload_hint(Object.new)).to include("each dispatch")
    end
  end
end
