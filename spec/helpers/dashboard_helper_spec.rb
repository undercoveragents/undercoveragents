# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardHelper do
  describe "#dashboard_operation_filter" do
    it "renders the selected operation and available choices" do
      operation = create(:operation, name: "Ops Alpha", icon: "fa-solid fa-briefcase")
      fragment = Nokogiri::HTML5.fragment(
        helper.dashboard_operation_filter(
          selected_operation: operation,
          selected_operation_icon: operation.icon,
          operations: [operation],
        ),
      )

      expect(fragment.at_css(".dash-op-filter")).to be_present
      expect(fragment.at_css(".dash-op-btn")&.text.to_s).to include("Ops Alpha")
      expect(fragment.css(".dash-op-item span").map(&:text)).to eq(["All Operations", "Ops Alpha"])
      expect(fragment.at_css(".dash-op-item.active span")&.text).to eq("Ops Alpha")
    end
  end

  describe "#format_token_count" do
    it "returns plain number for small counts" do
      expect(helper.format_token_count(500)).to eq("500")
    end

    it "formats thousands with K suffix" do
      expect(helper.format_token_count(1_500)).to eq("1.5K")
    end

    it "formats millions with M suffix" do
      expect(helper.format_token_count(2_500_000)).to eq("2.5M")
    end

    it "returns 0 for zero" do
      expect(helper.format_token_count(0)).to eq("0")
    end
  end

  describe "#getting_started_progress" do
    it "calculates progress correctly" do
      steps = [
        { done: true },
        { done: false },
        { done: true },
        { done: false },
      ]
      result = helper.getting_started_progress(steps)
      expect(result[:done]).to eq(2)
      expect(result[:total]).to eq(4)
      expect(result[:percentage]).to eq(50)
    end

    it "handles all complete" do
      steps = [{ done: true }, { done: true }]
      result = helper.getting_started_progress(steps)
      expect(result[:percentage]).to eq(100)
    end

    it "handles empty steps" do
      result = helper.getting_started_progress([])
      expect(result[:percentage]).to eq(0)
    end
  end

  describe "#getting_started_step_css" do
    it "returns done class for completed step" do
      expect(helper.getting_started_step_css({ done: true })).to eq("dashboard-step--done")
    end

    it "returns pending class for incomplete step" do
      expect(helper.getting_started_step_css({ done: false })).to eq("dashboard-step--pending")
    end
  end

  describe "#time_ago_short" do
    it "returns dash for nil" do
      expect(helper.time_ago_short(nil)).to eq("—")
    end

    it "returns just now for recent times" do
      expect(helper.time_ago_short(30.seconds.ago)).to eq("just now")
    end

    it "returns minutes for times within an hour" do
      expect(helper.time_ago_short(5.minutes.ago)).to eq("5m ago")
    end

    it "returns hours for times within a day" do
      expect(helper.time_ago_short(3.hours.ago)).to eq("3h ago")
    end

    it "returns days for times within a week" do
      expect(helper.time_ago_short(2.days.ago)).to eq("2d ago")
    end

    it "returns date for older times" do
      expect(helper.time_ago_short(2.weeks.ago)).to match(/\A[A-Z][a-z]{2} \d{2}\z/)
    end
  end

  describe "#stat_card_trend_icon" do
    it "returns up arrow for positive value" do
      expect(helper.stat_card_trend_icon(5)).to eq("fa-solid fa-arrow-trend-up")
    end

    it "returns down arrow for negative value" do
      expect(helper.stat_card_trend_icon(-3)).to eq("fa-solid fa-arrow-trend-down")
    end

    it "returns minus for zero" do
      expect(helper.stat_card_trend_icon(0)).to eq("fa-solid fa-minus")
    end
  end

  describe "#chat_status_badge_class" do
    it "returns secondary for idle chat" do
      chat = build(:chat, status: "idle")
      expect(helper.chat_status_badge_class(chat)).to eq("badge-secondary")
    end

    it "returns brand for streaming chat" do
      chat = build(:chat, status: "streaming")
      expect(helper.chat_status_badge_class(chat)).to eq("badge-brand")
    end

    it "returns warning for other statuses" do
      chat = build(:chat, status: "cancelled")
      expect(helper.chat_status_badge_class(chat)).to eq("badge-warning")
    end
  end

  describe "#mission_run_badge_class" do
    it "returns success for completed run" do
      run = build(:mission_run, status: "completed")
      expect(helper.mission_run_badge_class(run)).to eq("badge-success")
    end

    it "returns brand for running run" do
      run = build(:mission_run, status: "running")
      expect(helper.mission_run_badge_class(run)).to eq("badge-brand")
    end

    it "returns danger for failed run" do
      run = build(:mission_run, status: "failed")
      expect(helper.mission_run_badge_class(run)).to eq("badge-danger")
    end

    it "returns secondary for cancelled run" do
      run = build(:mission_run, status: "cancelled")
      expect(helper.mission_run_badge_class(run)).to eq("badge-secondary")
    end
  end

  describe "#test_run_badge_class" do
    it "returns success for completed run" do
      run = build(:test_suite_run, status: "completed")
      expect(helper.test_run_badge_class(run)).to eq("badge-success")
    end

    it "returns brand for running run" do
      run = build(:test_suite_run, status: "running")
      expect(helper.test_run_badge_class(run)).to eq("badge-brand")
    end

    it "returns brand for evaluating run" do
      run = build(:test_suite_run, status: "evaluating")
      expect(helper.test_run_badge_class(run)).to eq("badge-brand")
    end

    it "returns danger for failed run" do
      run = build(:test_suite_run, status: "failed")
      expect(helper.test_run_badge_class(run)).to eq("badge-danger")
    end

    it "returns secondary for cancelled run" do
      run = build(:test_suite_run, status: "cancelled")
      expect(helper.test_run_badge_class(run)).to eq("badge-secondary")
    end
  end
end
