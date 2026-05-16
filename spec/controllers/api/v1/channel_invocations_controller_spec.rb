# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::ChannelInvocationsController do
  describe "private helpers" do
    subject(:invocation_controller) { controller_class.new }

    let(:controller_class) do
      Class.new(described_class) do
        attr_writer :test_params

        def params = @test_params || super
      end
    end
    let(:channel) { build_stubbed(:channel, :api, name: "Public API") }
    let(:channel_target) { build_stubbed(:channel_target, :mission, channel:, name: "Webhook Mission") }

    before do
      invocation_controller.instance_variable_set(:@current_channel, channel)
      invocation_controller.instance_variable_set(:@channel_target, channel_target)
    end

    it "returns an empty payload when the payload param is blank" do
      invocation_controller.test_params = { payload: nil }

      expect(invocation_controller.send(:extract_payload)).to eq({})
    end

    it "falls back to to_h when the payload object does not expose to_unsafe_h" do
      raw_payload = Class.new do
        def to_h
          { "message" => "hello" }
        end
      end.new

      invocation_controller.test_params = { payload: raw_payload }

      expect(invocation_controller.send(:extract_payload)).to eq({ "message" => "hello" })
    end

    it "serializes present mission run timestamps and duration" do
      started_at = Time.zone.parse("2025-01-01 10:00:00 UTC")
      completed_at = started_at + 5.123
      run = instance_double(
        MissionRun,
        id: 123,
        status: "completed",
        started_at:,
        completed_at:,
        duration: 5.126,
        completed?: true,
        failed?: false,
        variables: {},
      )

      result = invocation_controller.send(:serialize_mission_run, run)

      expect(result).to include(
        started_at: started_at.iso8601,
        completed_at: completed_at.iso8601,
        duration: 5.13,
      )
    end
  end
end
