# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolCalls::Presentation do
  describe ".sanitize_icon" do
    it "normalizes supported icon aliases" do
      expect(described_class.sanitize_icon("fa-solid fa-sparkles")).to eq("fa-solid fa-wand-magic-sparkles")
    end

    it "returns nil for invalid icon input" do
      expect(described_class.sanitize_icon("javascript:alert(1)")).to be_nil
    end
  end

  describe ".normalize_messages" do
    it "strips blanks, deduplicates values, and caps the list length" do
      values = ["alpha", " ", "alpha"] + Array.new(60) { |index| "msg #{index}" }

      messages = described_class.normalize_messages(values)

      expect(messages.first).to eq("alpha")
      expect(messages).not_to include("")
      expect(messages.count("alpha")).to eq(1)
      expect(messages.size).to eq(described_class::MAX_MESSAGE_COUNT)
    end
  end

  describe ".normalize_running_mode" do
    it "falls back to the default mode for blank values" do
      expect(described_class.normalize_running_mode(nil)).to eq(described_class::DEFAULT_RUNNING_MODE)
    end

    it "falls back to the default mode for unsupported values" do
      expect(described_class.normalize_running_mode("zigzag")).to eq(described_class::DEFAULT_RUNNING_MODE)
    end

    it "preserves supported running modes" do
      expect(described_class.normalize_running_mode("rotate")).to eq("rotate")
    end
  end

  describe ".normalize_interval" do
    it "falls back to the default interval for non-integer values" do
      expect(described_class.normalize_interval("fast")).to eq(described_class::DEFAULT_RUNNING_INTERVAL_MS)
    end

    it "clamps supported intervals into the configured range" do
      expect(described_class.normalize_interval(100)).to eq(described_class::MIN_RUNNING_INTERVAL_MS)
      expect(described_class.normalize_interval(50_000)).to eq(described_class::MAX_RUNNING_INTERVAL_MS)
    end
  end

  describe ".normalize_group_title" do
    it "squishes whitespace and truncates long titles" do
      title = described_class.normalize_group_title("  Working   on   a   task  ")

      expect(title).to eq("Working on a task")
      expect(described_class.normalize_group_title("x" * 200).length)
        .to eq(described_class::MAX_GROUP_TITLE_LENGTH)
    end
  end

  describe "#widget_payload" do
    it "omits the initial phrase when the provided phrase is blank" do
      presentation = described_class.new(
        display_name: "Designer",
        icon: "fa-solid fa-wand-magic-sparkles",
        group_title: "Working on the mission flow",
        running_messages: ["Working"],
        complete_messages: ["Done"],
      )

      payload = presentation.widget_payload(status: "running", phrase: "   ")

      expect(payload).not_to have_key(:tool_widget_initial_phrase_value)
      expect(payload[:tool_widget_status_value]).to eq("running")
      expect(payload[:tool_widget_group_title_value]).to eq("Working on the mission flow")
      expect(presentation).to be_grouped
    end
  end
end
