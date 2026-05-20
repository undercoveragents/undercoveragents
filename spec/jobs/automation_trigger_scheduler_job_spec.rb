# frozen_string_literal: true

require "rails_helper"

RSpec.describe AutomationTriggerSchedulerJob do
  include ActiveSupport::Testing::TimeHelpers

  before do
    travel_to(Time.find_zone!("UTC").parse("2026-05-20 08:15:00"))
  end

  describe "#perform" do
    it "creates a mission run and enqueues execution for due schedule triggers" do
      trigger = create(
        :automation_trigger,
        :schedule,
        payload: { report_type: "daily" },
        cron_expression: "0 * * * *",
      )
      trigger.update_columns(next_run_at: 5.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

      expect do
        described_class.perform_now
      end.to change(MissionRun, :count).by(1)
      expect(Api::MissionExecutionJob).to have_been_enqueued.with(
        kind_of(Integer),
        tenant_id: trigger.schedulable.operation.tenant_id,
      )
    end

    it "continues polling when a batch fills the configured size" do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      first_trigger = create(:automation_trigger, :schedule, cron_expression: "0 * * * *")
      second_trigger = create(:automation_trigger, :schedule, cron_expression: "0 * * * *")
      first_trigger.update_columns(next_run_at: 5.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
      second_trigger.update_columns(next_run_at: 4.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

      expect { described_class.perform_now }.to change(MissionRun, :count).by(2)
    end

    it "returns early when a claimed trigger can no longer be dispatched" do
      job = described_class.new

      allow(job).to receive(:claim_due_trigger).and_return(nil)
      allow(AutomationTriggers::Dispatcher).to receive(:new)

      job.send(:dispatch_due_trigger, 123)

      expect(AutomationTriggers::Dispatcher).not_to have_received(:new)
    end

    it "returns nil from claim_due_trigger when the trigger no longer exists" do
      result = described_class.new.send(:claim_due_trigger, 0)

      expect(result).to be_nil
    end

    it "returns nil from claim_due_trigger when the trigger is not yet due" do
      trigger = create(:automation_trigger, :schedule, cron_expression: "0 * * * *")

      result = described_class.new.send(:claim_due_trigger, trigger.id)

      expect(result).to be_nil
    end

    it "records the last error when dispatch raises" do
      trigger = create(:automation_trigger, :schedule, cron_expression: "0 * * * *")
      trigger.update_columns(next_run_at: 5.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
      dispatcher = instance_double(AutomationTriggers::Dispatcher)
      allow(AutomationTriggers::Dispatcher).to receive(:new).and_return(dispatcher)
      allow(dispatcher).to receive(:call).and_raise(StandardError, "dispatch boom")
      allow(Rails.logger).to receive(:error)

      described_class.perform_now

      expect(trigger.reload.last_error).to eq("dispatch boom")
      expect(Rails.logger).to have_received(:error).with(/dispatch boom/)
    end

    it "logs dispatch errors even when the trigger is missing" do
      allow(Rails.logger).to receive(:error)

      expect do
        described_class.new.send(:record_dispatch_error, 123, nil, StandardError.new("missing trigger"))
      end.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(/missing trigger/)
    end
  end
end
