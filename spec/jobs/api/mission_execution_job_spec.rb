# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::MissionExecutionJob do
  let(:tenant) { create(:tenant) }
  let(:operation) { create(:operation, tenant:) }
  let(:mission) { create(:mission, operation:) }
  let(:run) { create(:mission_run, mission:) }

  describe "#perform" do
    it "executes the mission run via Runner" do
      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(mission).and_return(runner)
      allow(runner).to receive(:resume_or_execute)

      described_class.perform_now(run.id, tenant_id: mission.operation.tenant_id)

      expect(runner).to have_received(:resume_or_execute).with(run, variables: {}, trigger_data: run.trigger_data)
    end

    it "supports mission execution without tenant scope for backward compatibility" do
      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(mission).and_return(runner)
      allow(runner).to receive(:resume_or_execute)

      described_class.perform_now(run.id)

      expect(runner).to have_received(:resume_or_execute).with(run, variables: {}, trigger_data: run.trigger_data)
    end

    it "enqueues callback delivery when callback_url is present" do
      run.update!(callback_url: "https://example.com/callback", status: "completed")
      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(mission).and_return(runner)
      allow(runner).to receive(:resume_or_execute)

      expect do
        described_class.perform_now(run.id, tenant_id: mission.operation.tenant_id)
      end.to have_enqueued_job(Api::CallbackDeliveryJob).with(run.id, tenant_id: mission.operation.tenant_id)
    end

    it "does not execute a run outside the provided tenant" do
      foreign_tenant = create(:tenant)
      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).and_return(runner)
      allow(runner).to receive(:resume_or_execute)

      described_class.perform_now(run.id, tenant_id: foreign_tenant.id)

      expect(runner).not_to have_received(:resume_or_execute)
    end

    it "does not enqueue callback when callback_url is blank" do
      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(mission).and_return(runner)
      allow(runner).to receive(:resume_or_execute)

      expect do
        described_class.perform_now(run.id, tenant_id: mission.operation.tenant_id)
      end.not_to have_enqueued_job(Api::CallbackDeliveryJob)
    end

    it "discards when run is not found" do
      expect { described_class.perform_now(999_999, tenant_id: create(:tenant).id) }.not_to raise_error
    end
  end
end
