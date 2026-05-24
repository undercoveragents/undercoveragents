# frozen_string_literal: true

# == Schema Information
#
# Table name: automation_triggers
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  cron_expression         :string
#  enabled                 :boolean          default(TRUE), not null
#  last_error              :text
#  last_result_record_type :string
#  last_triggered_at       :datetime
#  name                    :string           not null
#  next_run_at             :datetime
#  payload                 :jsonb            not null
#  schedulable_type        :string           not null
#  timezone                :string           default("UTC"), not null
#  trigger_type            :string           not null
#  webhook_secret_digest   :string
#  webhook_secret_prefix   :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  last_result_record_id   :bigint
#  operation_id            :bigint           not null
#  schedulable_id          :bigint           not null
#
# Indexes
#
#  index_automation_triggers_on_last_result_record    (last_result_record_type,last_result_record_id)
#  index_automation_triggers_on_operation_id          (operation_id)
#  index_automation_triggers_on_schedulable           (schedulable_type,schedulable_id)
#  index_automation_triggers_on_schedulable_and_name  (schedulable_type,schedulable_id,name) UNIQUE
#  index_automation_triggers_on_schedule_state        (trigger_type,enabled,next_run_at)
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
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
