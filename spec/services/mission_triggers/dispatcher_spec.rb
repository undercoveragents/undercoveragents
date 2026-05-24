# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionTriggers::Dispatcher do
  let(:mission) { create(:mission) }
  let(:mission_trigger) { create(:mission_trigger, :webhook, mission:, payload: default_payload) }
  let(:default_payload) { {} }

  describe "#call" do
    it "accepts nil payloads" do
      allow(mission).to receive(:filter_trigger_data) { |payload| payload }
      allow(mission).to receive(:validate_required_inputs).and_return([])

      run = described_class.new(mission_trigger:, source: :webhook, payload: nil).call

      expect(run.trigger_data).to eq({})
      expect(run.execution_state.dig("trigger", "source")).to eq("webhook")
    end

    it "accepts action controller parameters payloads" do
      allow(mission).to receive(:filter_trigger_data) { |payload| payload }
      allow(mission).to receive(:validate_required_inputs).and_return([])

      run = described_class.new(
        mission_trigger:,
        source: :schedule,
        payload: ActionController::Parameters.new(event: "invoice.created"),
      ).call

      expect(run.trigger_data).to eq({ "event" => "invoice.created" })
      expect(run.execution_state.dig("trigger", "trigger_type")).to eq("webhook")
    end

    it "records validation failures on the trigger" do
      allow(mission).to receive_messages(
        filter_trigger_data: {},
        validate_required_inputs: ["event"],
      )

      expect do
        described_class.new(mission_trigger:, source: :webhook, payload: nil).call
      end.to raise_error(described_class::InvalidPayload, "Missing required fields: event")

      expect(mission_trigger.reload.last_error).to eq("Missing required fields: event")
    end

    it "rejects invalid payload objects" do
      expect do
        described_class.new(mission_trigger:, source: :webhook, payload: "bad").call
      end.to raise_error(described_class::InvalidPayload, "Trigger payload must be a JSON object")

      expect(mission_trigger.reload.last_error).to eq("Trigger payload must be a JSON object")
    end
  end
end
