# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Delay do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns delay" do
      expect(described_class.node_type).to eq("delay")
    end
  end

  describe ".node_category" do
    it "is control" do
      expect(described_class.node_category).to eq(:control)
    end
  end

  describe ".required_field_keys" do
    it "requires duration" do
      expect(described_class.required_field_keys).to eq(["duration"])
    end
  end

  describe ".variable_schema" do
    it "declares waited_seconds variable" do
      schema = described_class.variable_schema

      expect(schema.outputs.map(&:name)).to include("waited")
    end
  end

  describe "#output_ports" do
    it "has a single default port" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end
  end

  describe "#execute" do
    before do
      allow(node).to receive(:sleep)
    end

    it "waits for the specified duration" do
      context.set_variable("_current_node_data", { "duration" => "0.01", "unit" => "seconds" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["waited"]).to eq(0.01)
    end

    it "converts minutes to seconds" do
      context.set_variable("_current_node_data", { "duration" => "0.01", "unit" => "minutes" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["waited"]).to eq(0.6)
    end

    it "defaults to seconds" do
      context.set_variable("_current_node_data", { "duration" => "0.01" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["waited"]).to eq(0.01)
    end

    it "fails with negative duration" do
      context.set_variable("_current_node_data", { "duration" => "-5" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Invalid delay")
    end

    it "fails when exceeding max delay" do
      context.set_variable("_current_node_data", { "duration" => "999" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("exceeds maximum")
    end

    it "fails with non-numeric duration" do
      context.set_variable("_current_node_data", { "duration" => "abc" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Invalid delay")
    end

    it "interpolates variable in duration" do
      context.set_variable("wait_time", "0.01")
      context.set_variable("_current_node_data", { "duration" => "{{wait_time}}" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["waited"]).to eq(0.01)
    end

    it "evaluates an expression in duration" do
      context.set_variable("base_delay", 0.005)
      context.set_variable("_current_node_data", { "duration" => "base_delay * 2" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["waited"]).to eq(0.01)
    end

    it "skips sleep when duration is zero" do
      context.set_variable("_current_node_data", { "duration" => "0" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["waited"]).to eq(0.0)
    end
  end
end
