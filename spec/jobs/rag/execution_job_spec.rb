# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::ExecutionJob do
  let(:tenant) { create(:tenant) }
  let(:operation) { create(:operation, tenant:) }
  let(:pipeline) { create(:rag_flow, operation:) }

  describe "#perform" do
    it "calls PipelineExecutor with the pipeline" do
      allow(Rag::PipelineExecutor).to receive(:call)
      described_class.perform_now(pipeline.id, tenant_id: tenant.id, triggered_by: "manual")
      expect(Rag::PipelineExecutor).to have_received(:call).with(pipeline, triggered_by: "manual", run: nil)
    end

    it "supports execution without tenant scope for backward compatibility" do
      run = create(:rag_run, rag_flow: pipeline, status: :running)
      allow(Rag::PipelineExecutor).to receive(:call)

      described_class.perform_now(pipeline.id, triggered_by: "manual", run_id: run.id)

      expect(Rag::PipelineExecutor).to have_received(:call).with(pipeline, triggered_by: "manual", run:)
    end

    it "discards when pipeline not found" do
      expect { described_class.perform_now(-1, tenant_id: create(:tenant).id) }.not_to raise_error
    end

    it "does not execute a pipeline outside the provided tenant" do
      foreign_tenant = create(:tenant)
      allow(Rag::PipelineExecutor).to receive(:call)

      described_class.perform_now(pipeline.id, tenant_id: foreign_tenant.id, triggered_by: "manual")

      expect(Rag::PipelineExecutor).not_to have_received(:call)
    end

    it "catches ExecutionError and logs it" do
      allow(Rag::PipelineExecutor).to receive(:call)
        .and_raise(Rag::PipelineExecutor::ExecutionError, "Step failed")
      allow(Rails.logger).to receive(:error)

      described_class.perform_now(pipeline.id, tenant_id: tenant.id)

      expect(Rails.logger).to have_received(:error).with(/Step failed/)
    end

    it "catches unexpected StandardError and logs it" do
      allow(Rag::PipelineExecutor).to receive(:call)
        .and_raise(StandardError, "something unexpected")
      allow(Rails.logger).to receive(:error)

      described_class.perform_now(pipeline.id, tenant_id: tenant.id)

      expect(Rails.logger).to have_received(:error).with(/unexpected/)
    end

    it "catches StandardError and marks existing run as failed" do
      run = create(:rag_run, rag_flow: pipeline, status: :running)
      allow(Rag::PipelineExecutor).to receive(:call)
        .and_raise(StandardError, "boom")
      allow(Rails.logger).to receive(:error)

      described_class.perform_now(pipeline.id, tenant_id: tenant.id, run_id: run.id)

      run.reload
      expect(run.status).to eq("failed")
      expect(run.error_message).to eq("boom")
    end

    it "does not update run when already finished" do
      run = create(:rag_run, rag_flow: pipeline, status: :completed,
                             completed_at: 1.minute.ago,)
      allow(Rag::PipelineExecutor).to receive(:call)
        .and_raise(StandardError, "boom")
      allow(Rails.logger).to receive(:error)

      described_class.perform_now(pipeline.id, tenant_id: tenant.id, run_id: run.id)

      run.reload
      expect(run.status).to eq("completed")
    end

    it "does not overwrite a run completed after the job loaded it" do
      run = create(:rag_run, rag_flow: pipeline, status: :running)
      allow(Rag::PipelineExecutor).to receive(:call) do
        run.update!(status: :completed, completed_at: Time.current)
        raise StandardError, "boom"
      end
      allow(Rails.logger).to receive(:error)

      described_class.perform_now(pipeline.id, tenant_id: tenant.id, run_id: run.id)

      run.reload
      expect(run.status).to eq("completed")
    end

    it "passes existing run to PipelineExecutor" do
      run = create(:rag_run, rag_flow: pipeline, status: :running)
      allow(Rag::PipelineExecutor).to receive(:call)

      described_class.perform_now(pipeline.id, tenant_id: tenant.id, run_id: run.id)

      expect(Rag::PipelineExecutor).to have_received(:call).with(pipeline, triggered_by: "manual", run:)
    end
  end
end
