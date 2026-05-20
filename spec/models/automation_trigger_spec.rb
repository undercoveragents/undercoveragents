# frozen_string_literal: true

require "rails_helper"

RSpec.describe AutomationTrigger do
  describe ".generate_webhook_secret" do
    it "returns prefixed raw, prefix, and digest values" do
      secret = described_class.generate_webhook_secret

      expect(secret[:raw_secret]).to start_with("atw_")
      expect(secret[:prefix]).to start_with("atw_")
      expect(secret[:digest]).to eq(Digest::SHA256.hexdigest(secret[:raw_secret]))
    end
  end

  describe "#payload" do
    it "normalizes non-hash payloads to an empty hash" do
      trigger = build(:automation_trigger)
      trigger[:payload] = ["unexpected"]

      expect(trigger.payload).to eq({})
    end
  end

  describe "#schedulable_label" do
    it "falls back to the raw schedulable type when it is unknown" do
      trigger = build(:automation_trigger)
      trigger.schedulable_type = "CustomThing"

      expect(trigger.schedulable_label).to eq("CustomThing")
    end
  end

  describe "#sync_operation_from_schedulable" do
    it "copies the operation from the schedulable when operation is not pre-set" do
      mission = create(:mission)
      trigger = build(:automation_trigger, target: mission, operation: nil)

      trigger.valid?

      expect(trigger.operation).to eq(mission.operation)
    end
  end

  describe "validations" do
    it "rejects triggers whose operation does not match the schedulable record" do
      mission = create(:mission)
      other_operation = create(:operation, tenant: mission.operation.tenant)
      trigger = build(:automation_trigger, target: mission, operation: other_operation)

      expect(trigger).not_to be_valid
      expect(trigger.errors[:operation]).to include("must match the scheduled record's operation")
    end
  end
end
