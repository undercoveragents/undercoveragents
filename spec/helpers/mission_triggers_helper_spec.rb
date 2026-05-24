# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionTriggersHelper do
  describe "#mission_trigger_icon" do
    it "returns the icon for a schedule trigger" do
      expect(helper.mission_trigger_icon("schedule")).to eq("fa-solid fa-clock")
    end

    it "returns the icon for a webhook trigger object" do
      expect(helper.mission_trigger_icon(build(:mission_trigger, :webhook))).to eq("fa-solid fa-link")
    end

    it "returns the fallback icon for unknown types" do
      expect(helper.mission_trigger_icon("custom")).to eq("fa-solid fa-bolt")
    end
  end

  describe "#mission_trigger_label" do
    it "returns Webhook for webhook triggers" do
      expect(helper.mission_trigger_label("webhook")).to eq("Webhook")
    end

    it "returns Schedule for other trigger types" do
      expect(helper.mission_trigger_label(build(:mission_trigger, :schedule))).to eq("Schedule")
    end
  end

  describe "#mission_trigger_webhook_url" do
    it "builds an absolute webhook url" do
      trigger = create(:mission_trigger, :webhook)
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, base_url: "https://app.example.com"))

      expect(helper.mission_trigger_webhook_url(trigger)).to eq("https://app.example.com/api/v1/mission_webhooks/#{trigger.id}")
    end
  end

  describe "#mission_trigger_status_badges" do
    it "returns label and active badges" do
      trigger = build(:mission_trigger, :schedule, enabled: true)

      badges = helper.mission_trigger_status_badges(trigger)

      expect(badges.first).to include("Schedule")
      expect(badges.second).to include("Active")
      expect(badges.second).to include("badge-success")
    end

    it "returns a disabled badge for inactive triggers" do
      trigger = build(:mission_trigger, :schedule, enabled: false)

      expect(helper.mission_trigger_status_badges(trigger).second).to include("Disabled", "badge-danger")
    end
  end

  describe "#mission_trigger_last_activity" do
    it "returns a fallback when the trigger never ran" do
      trigger = build(:mission_trigger, last_triggered_at: nil)

      expect(helper.mission_trigger_last_activity(trigger)).to eq("Never triggered")
    end

    it "formats the last activity label" do
      trigger = build(:mission_trigger, last_triggered_at: 2.hours.ago)
      allow(helper).to receive(:time_ago_in_words).with(trigger.last_triggered_at).and_return("about 2 hours")

      expect(helper.mission_trigger_last_activity(trigger)).to eq("Triggered about 2 hours ago")
    end
  end

  describe "#mission_trigger_next_run_label" do
    it "returns Disabled for inactive triggers" do
      expect(helper.mission_trigger_next_run_label(build(:mission_trigger, enabled: false))).to eq("Disabled")
    end

    it "returns Not scheduled when there is no next run" do
      expect(helper.mission_trigger_next_run_label(build(:mission_trigger, next_run_at: nil))).to eq("Not scheduled")
    end

    it "formats the next run timestamp" do
      trigger = build(:mission_trigger, next_run_at: Time.find_zone!("UTC").parse("2026-05-20 09:00:00"))
      allow(helper).to receive(:l).with(trigger.next_run_at, format: :long).and_return("May 20, 2026 09:00")

      expect(helper.mission_trigger_next_run_label(trigger)).to eq("Next run May 20, 2026 09:00")
    end
  end

  describe "#mission_trigger_edit_actions" do
    let(:mission) { create(:mission) }

    before do
      allow(helper).to receive_messages(
        page_hero_form_action: :save_action,
        policy_page_hero_action: :regenerate_action,
      )
    end

    it "returns only the save action for schedule triggers" do
      trigger = build(:mission_trigger, :schedule, mission:)

      expect(helper.mission_trigger_edit_actions(mission:, mission_trigger: trigger)).to eq([:save_action])
    end

    it "prepends the regenerate action for webhook triggers" do
      trigger = create(:mission_trigger, :webhook, mission:)

      expect(helper.mission_trigger_edit_actions(mission:, mission_trigger: trigger)).to eq(
        [:regenerate_action, :save_action],
      )
    end
  end

  describe "#mission_trigger_curl_example" do
    it "uses the real webhook url for persisted triggers" do
      trigger = create(:mission_trigger, :webhook)
      allow(helper).to receive(:mission_trigger_webhook_url).with(trigger).and_return("https://app.example.com/api/v1/mission_webhooks/#{trigger.id}")

      curl = helper.mission_trigger_curl_example(trigger, webhook_secret: "mtw_secret")

      expect(curl).to include("https://app.example.com/api/v1/mission_webhooks/#{trigger.id}")
      expect(curl).to include(%(#{MissionTrigger::WEBHOOK_SECRET_HEADER}: mtw_secret))
    end

    it "uses the placeholder url and secret for unsaved triggers" do
      curl = helper.mission_trigger_curl_example(build(:mission_trigger, :webhook), webhook_secret: nil)

      expect(curl).to include("https://your-app.example.com/api/v1/mission_webhooks/TRIGGER_ID")
      expect(curl).to include("<your secret>")
    end
  end
end
