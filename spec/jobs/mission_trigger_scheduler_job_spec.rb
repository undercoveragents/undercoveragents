# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionTriggerSchedulerJob do
  include ActiveSupport::Testing::TimeHelpers

  describe "#perform" do
    before do
      travel_to(Time.find_zone!("UTC").parse("2026-05-20 08:15:00"))
    end

    it "creates a mission run and enqueues execution for due schedule triggers" do
      trigger = create(
        :mission_trigger,
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
        tenant_id: trigger.mission.operation.tenant_id,
      )

      run = MissionRun.last
      expect(run.trigger_data).to eq({ "report_type" => "daily" })
      expect(run.execution_state.dig("trigger", "mission_trigger_id")).to eq(trigger.id)
    end

    it "updates trigger bookkeeping after a dispatch" do
      trigger = create(:mission_trigger, :schedule, cron_expression: "0 * * * *")
      trigger.update_columns(next_run_at: 5.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

      described_class.perform_now

      trigger.reload
      expect(trigger.last_mission_run).to eq(MissionRun.last)
      expect(trigger.last_triggered_at).to be_within(2.seconds).of(Time.current)
      expect(trigger.next_run_at).to eq(Time.find_zone!("UTC").parse("2026-05-20 09:00:00"))
      expect(trigger.last_error).to be_nil
    end

    it "ignores triggers that are not due yet" do
      trigger = create(:mission_trigger, :schedule, cron_expression: "0 * * * *")

      expect { described_class.perform_now }.not_to change(MissionRun, :count)
      expect(trigger.reload.last_triggered_at).to be_nil
    end

    it "continues polling when a batch fills the configured size" do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      first_trigger = create(:mission_trigger, :schedule, cron_expression: "0 * * * *")
      second_trigger = create(:mission_trigger, :schedule, cron_expression: "0 * * * *")
      first_trigger.update_columns(next_run_at: 5.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
      second_trigger.update_columns(next_run_at: 4.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

      expect { described_class.perform_now }.to change(MissionRun, :count).by(2)
    end

    it "skips dispatch when a claimed trigger is no longer available" do
      job = described_class.new

      allow(MissionTrigger).to receive(:transaction).and_yield
      allow(MissionTrigger).to receive(:lock).with("FOR UPDATE SKIP LOCKED").and_return(MissionTrigger)
      allow(MissionTrigger).to receive(:find_by).and_return(nil)

      expect(job.send(:claim_due_trigger, 999_999)).to be_nil
    end

    it "records the last error when dispatch raises" do
      trigger = create(:mission_trigger, :schedule, cron_expression: "0 * * * *")
      trigger.update_columns(next_run_at: 5.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
      dispatcher = instance_double(MissionTriggers::Dispatcher)
      allow(MissionTriggers::Dispatcher).to receive(:new).and_return(dispatcher)
      allow(dispatcher).to receive(:call).and_raise(StandardError, "dispatch boom")
      allow(Rails.logger).to receive(:error)

      described_class.perform_now

      expect(trigger.reload.last_error).to eq("dispatch boom")
      expect(Rails.logger).to have_received(:error).with(/dispatch boom/)
    end

    it "returns early when a due trigger can no longer be claimed" do
      job = described_class.new

      allow(job).to receive(:claim_due_trigger).and_return(nil)
      allow(MissionTriggers::Dispatcher).to receive(:new)

      job.send(:dispatch_due_trigger, 123)

      expect(MissionTriggers::Dispatcher).not_to have_received(:new)
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
