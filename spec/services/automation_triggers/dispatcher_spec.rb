# frozen_string_literal: true

require "rails_helper"

RSpec.describe AutomationTriggers::Dispatcher do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }

  describe "#call" do
    it "returns a mission run with merged trigger data and job enqueued" do
      mission = create(:mission, operation:)
      trigger = create(:automation_trigger, :schedule, target: mission, payload: { "default" => "value" })

      result = described_class.new(
        automation_trigger: trigger,
        source: :schedule,
        payload: ActionController::Parameters.new("runtime" => "value"),
      ).call

      expect(result).to be_a(MissionRun)
      expect(result.trigger_data).to eq({ "default" => "value", "runtime" => "value" })
      expect(result.execution_state.dig("trigger", "automation_trigger_id")).to eq(trigger.id)
      expect(Api::MissionExecutionJob).to have_been_enqueued.with(result.id, tenant_id: tenant.id)
    end

    it "updates last_result_record and clears last_error on mission dispatch success" do
      mission = create(:mission, operation:)
      trigger = create(:automation_trigger, :schedule, target: mission)

      result = described_class.new(
        automation_trigger: trigger,
        source: :schedule,
        payload: nil,
      ).call

      expect(trigger.reload.last_result_record).to eq(result)
      expect(trigger.last_error).to be_nil
    end

    it "dispatches a rag-flow trigger and stores the merged payload in run stats" do
      rag_flow = create(:rag_flow, operation:)
      allow(rag_flow).to receive_messages(runnable?: true, fully_configured?: true)
      trigger = create(:automation_trigger, :webhook, target: rag_flow, payload: { "source" => "default" })

      result = described_class.new(
        automation_trigger: trigger,
        source: :webhook,
        payload: { "event" => "refresh" },
      ).call

      expect(result).to be_a(RagRun)
      expect(result.triggered_by).to eq("webhook")
      expect(result.stats).to include(
        "payload" => { "source" => "default", "event" => "refresh" },
      )
      expect(result.stats.dig("trigger", "automation_trigger_id")).to eq(trigger.id)
      expect(Rag::ExecutionJob).to have_been_enqueued.with(
        rag_flow.id,
        tenant_id: tenant.id,
        triggered_by: "webhook",
        run_id: result.id,
      )
    end

    it "omits payload stats when the merged payload is blank" do
      rag_flow = create(:rag_flow, operation:)
      allow(rag_flow).to receive_messages(runnable?: true, fully_configured?: true)
      trigger = create(:automation_trigger, :schedule, target: rag_flow, payload: {})

      result = described_class.new(automation_trigger: trigger, source: :schedule, payload: nil).call

      expect(result.triggered_by).to eq("scheduled")
      expect(result.stats).not_to have_key("payload")
    end

    it "rejects unsupported schedulable targets and records the failure" do
      trigger = build(:automation_trigger)
      allow(trigger).to receive_messages(schedulable: Object.new, schedulable_type: "UnknownThing")
      allow(trigger).to receive(:update)

      expect do
        described_class.new(automation_trigger: trigger, source: :schedule).call
      end.to raise_error(described_class::InvalidPayload, "Unsupported automation target 'UnknownThing'.")

      expect(trigger).to have_received(:update).with(last_error: "Unsupported automation target 'UnknownThing'.")
    end

    it "rejects invalid payload objects" do
      trigger = create(:automation_trigger, :schedule)

      expect do
        described_class.new(automation_trigger: trigger, source: :schedule, payload: "bad").call
      end.to raise_error(described_class::InvalidPayload, "Trigger payload must be a JSON object")

      expect(trigger.reload.last_error).to eq("Trigger payload must be a JSON object")
    end

    it "rejects disabled rag flows" do
      rag_flow = create(:rag_flow, operation:)
      allow(rag_flow).to receive_messages(runnable?: false, fully_configured?: true)
      trigger = create(:automation_trigger, :schedule, target: rag_flow)

      expect do
        described_class.new(automation_trigger: trigger, source: :schedule).call
      end.to raise_error(described_class::InvalidPayload, "RAG flow must be enabled to run.")
    end

    it "rejects rag flows that are not fully configured" do
      rag_flow = create(:rag_flow, operation:)
      allow(rag_flow).to receive_messages(runnable?: true, fully_configured?: false)
      trigger = create(:automation_trigger, :schedule, target: rag_flow)

      expect do
        described_class.new(automation_trigger: trigger, source: :schedule).call
      end.to raise_error(described_class::InvalidPayload, "RAG flow must be fully configured to run.")
    end
  end
end
