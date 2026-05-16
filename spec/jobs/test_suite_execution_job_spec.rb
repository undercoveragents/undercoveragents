# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuiteExecutionJob do
  let(:tenant) { create(:tenant) }
  let(:operation) { create(:operation, tenant:) }
  let(:agent) { create(:agent, operation:) }
  let(:mission) { create(:mission, operation:) }
  let(:test_suite) { create(:test_suite, :with_test_cases, agent:) }
  let(:run) { TestSuites::CreateRunService.call(test_suite) }

  describe "#perform" do
    it "calls the execution service for agent suites" do
      allow(TestSuites::ExecutionService).to receive(:call)

      described_class.new.perform(run.id, tenant_id: tenant.id)

      expect(TestSuites::ExecutionService).to have_received(:call).with(run)
    end

    it "supports execution without tenant scope for backward compatibility" do
      allow(TestSuites::ExecutionService).to receive(:call)

      described_class.new.perform(run.id)

      expect(TestSuites::ExecutionService).to have_received(:call).with(run)
    end

    context "when the suite is a mission suite" do
      let(:test_suite) { create(:test_suite, :mission_suite, :with_test_cases, mission:) }

      it "calls the mission execution service" do
        allow(TestSuites::MissionExecutionService).to receive(:call)

        described_class.new.perform(run.id, tenant_id: tenant.id)

        expect(TestSuites::MissionExecutionService).to have_received(:call).with(run)
      end
    end

    it "does not execute a run outside the provided tenant" do
      foreign_tenant = create(:tenant)
      allow(TestSuites::ExecutionService).to receive(:call)

      described_class.new.perform(run.id, tenant_id: foreign_tenant.id)

      expect(TestSuites::ExecutionService).not_to have_received(:call)
    end

    context "when the run is cancelled" do
      before { run.update!(status: :cancelled) }

      it "does not call the execution service" do
        allow(TestSuites::ExecutionService).to receive(:call)

        described_class.new.perform(run.id, tenant_id: tenant.id)

        expect(TestSuites::ExecutionService).not_to have_received(:call)
      end
    end

    context "when an error occurs" do
      before do
        allow(TestSuites::ExecutionService).to receive(:call).and_raise(StandardError, "boom")
        allow(Rails.logger).to receive(:error)
      end

      it "marks the run as failed" do
        described_class.new.perform(run.id, tenant_id: tenant.id)

        run.reload
        expect(run).to be_failed
        expect(run.completed_at).to be_present
      end

      it "logs the error" do
        described_class.new.perform(run.id, tenant_id: tenant.id)

        expect(Rails.logger).to have_received(:error).with(/boom/)
      end

      it "does not overwrite a run completed before rescue handling" do
        allow(TestSuites::ExecutionService).to receive(:call) do
          run.update!(status: :completed, completed_at: Time.current)
          raise StandardError, "boom"
        end

        described_class.new.perform(run.id, tenant_id: tenant.id)

        run.reload
        expect(run).to be_completed
      end
    end

    context "when the run ID does not exist" do
      before { allow(Rails.logger).to receive(:error) }

      it "handles gracefully without raising" do
        expect { described_class.new.perform(-999, tenant_id: create(:tenant).id) }.not_to raise_error
        expect(Rails.logger).to have_received(:error)
      end
    end

    it "handles errors raised before a run is loaded" do
      job = described_class.new
      allow(job).to receive(:find_run).and_raise(StandardError, "boom")
      allow(Rails.logger).to receive(:error)

      expect { job.perform(run.id, tenant_id: tenant.id) }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/boom/)
    end
  end
end
