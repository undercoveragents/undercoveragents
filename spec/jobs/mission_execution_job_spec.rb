# frozen_string_literal: true

require "rails_helper"
require "support/mission_flow_builder"

RSpec.describe MissionExecutionJob do
  before do
    MissionNodePlugin.reset!

    MissionNodePlugin.register(
      "input", "Missions::Nodes::Input",
      label: "Input", icon: "fa-solid fa-right-to-bracket", color: "#10b981",
      category: :input_output, description: "Receives input fields",
    )
    MissionNodePlugin.register(
      "output", "Missions::Nodes::Output",
      label: "Output", icon: "fa-solid fa-arrow-right-from-bracket", color: "#ec4899",
      category: :input_output, description: "Selects variables to output",
    )
    MissionNodePlugin.register(
      "set_variable", "Missions::Nodes::SetVariable",
      label: "Set Variable", icon: "fa-solid fa-equals", color: "#84cc16",
      category: :control, description: "Sets variables",
    )

    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow_any_instance_of(Missions::DebugRunner).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
  end

  after { MissionNodePlugin.restore_defaults! }

  describe "#perform" do
    it "executes a run and marks it completed" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "pending", flow_snapshot: flow)

      described_class.new.perform(run.id, tenant_id: mission.operation.tenant_id, variables: { "input" => "hello" })

      run.reload
      expect(run).to be_completed
    end

    it "handles a missing MissionRun gracefully" do
      allow(Rails.logger).to receive(:error)

      described_class.new.perform(999_999, tenant_id: create(:tenant).id)

      expect(Rails.logger).to have_received(:error).with(/MissionRun 999999 not found/)
    end

    it "omits the tenant suffix when no tenant id is provided" do
      expect(described_class.new.send(:tenant_scope_log_suffix, nil)).to eq("")
    end

    it "does not execute a run outside the provided tenant" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "pending", flow_snapshot: flow)
      foreign_tenant = create(:tenant)

      allow(Rails.logger).to receive(:error)

      described_class.new.perform(run.id, tenant_id: foreign_tenant.id, variables: { "input" => "hello" })

      run.reload
      expect(run).to be_pending
      expect(Rails.logger).to have_received(:error).with(
        /MissionRun #{run.id} not found for tenant #{foreign_tenant.id}/,
      )
    end

    it "marks the run as failed when an unhandled error occurs" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "pending", flow_snapshot: flow)

      # Force the runner to raise outside its own rescue
      allow_any_instance_of(Missions::DebugRunner).to receive(:resume_or_execute) # rubocop:disable RSpec/AnyInstance
        .and_raise(StandardError, "unexpected crash")

      allow(Rails.logger).to receive(:error)

      described_class.new.perform(run.id, tenant_id: mission.operation.tenant_id, variables: { "input" => "test" })

      run.reload
      expect(run).to be_failed
      expect(run.error).to include("unexpected crash")
      expect(run.completed_at).to be_present
      expect(Rails.logger).to have_received(:error).with(/Unhandled error/)
    end

    it "does not re-fail an already-failed run" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "failed", flow_snapshot: flow,
                                 error: "previous error", completed_at: 1.minute.ago,)

      allow_any_instance_of(Missions::DebugRunner).to receive(:resume_or_execute) # rubocop:disable RSpec/AnyInstance
        .and_raise(StandardError, "new crash")

      allow(Rails.logger).to receive(:error)

      described_class.new.perform(run.id, tenant_id: mission.operation.tenant_id, variables: {})

      run.reload
      expect(run.error).to eq("previous error")
      expect(Rails.logger).to have_received(:error).with(/Unhandled error/)
    end

    it "does not overwrite a run completed before rescue handling" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "pending", flow_snapshot: flow)

      allow_any_instance_of(Missions::DebugRunner).to receive(:resume_or_execute) do # rubocop:disable RSpec/AnyInstance
        MissionRun.where(id: run.id).update_all(status: "completed", completed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        raise StandardError, "post-completion crash"
      end

      allow(Rails.logger).to receive(:error)

      described_class.new.perform(run.id, tenant_id: mission.operation.tenant_id, variables: { "input" => "test" })

      run.reload
      expect(run).to be_completed
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end

    it "logs error when safely_fail_run broadcast raises" do
      flow = MissionFlowBuilder.build do |f|
        f.node("t1", type: "input")
        f.node("o1", type: "output")
        f.edge("t1", "o1")
      end

      mission = create(:mission, flow_data: flow)
      run = create(:mission_run, mission:, status: "pending", flow_snapshot: flow)

      # Runner raises, so the job calls safely_fail_run.
      # update! succeeds but both Turbo broadcasts raise.
      allow_any_instance_of(Missions::DebugRunner).to receive(:resume_or_execute) # rubocop:disable RSpec/AnyInstance
        .and_raise(StandardError, "initial crash")
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(StandardError, "broadcast crash")
      allow(Rails.logger).to receive(:error)

      described_class.new.perform(run.id, tenant_id: mission.operation.tenant_id, variables: { "input" => "test" })

      run.reload
      expect(run).to be_failed
      expect(Rails.logger).to have_received(:error).with(/Failed to broadcast failure/)
    end

    it "does not call safely_fail_run when run lookup itself raises" do
      allow(MissionRun).to receive(:find_by).and_raise(StandardError, "DB error")
      allow(Rails.logger).to receive(:error)

      expect { described_class.new.perform(999) }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/Unhandled error/)
    end
  end
end
