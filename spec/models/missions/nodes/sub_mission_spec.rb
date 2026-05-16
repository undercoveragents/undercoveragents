# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::SubMission do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns mission" do
      expect(described_class.node_type).to eq("mission")
    end
  end

  describe ".node_category" do
    it "is node" do
      expect(described_class.node_category).to eq(:node)
    end
  end

  describe ".required_field_keys" do
    it "requires mission_id" do
      expect(described_class.required_field_keys).to eq(["mission_id"])
    end
  end

  describe ".variable_schema" do
    it "declares output variable" do
      schema = described_class.variable_schema
      names = schema.outputs.map(&:name)

      expect(names).to include("output")
    end
  end

  describe "#output_ports" do
    it "has a default port" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end
  end

  describe "#execute" do
    it "fails when no mission_id is configured" do
      context.set_variable("_current_node_data", { "mission_id" => "" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("No mission_id configured")
    end

    it "fails when mission is not found" do
      context.set_variable("_current_node_data", { "mission_id" => "nonexistent" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Mission not found")
    end

    it "fails when nesting depth exceeds maximum" do
      sub_mission = create(:mission)
      context.set_variable("_nesting_depth", Missions::Nodes::SubMission::MAX_NESTING_DEPTH)
      context.set_variable("_current_node_data", { "mission_id" => sub_mission.id.to_s })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Maximum nesting depth")
    end

    it "executes sub-mission and returns output" do
      sub_mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })
      context.set_variable("_current_node_data", { "mission_id" => sub_mission.id.to_s })

      completed_run = instance_double(MissionRun, completed?: true, variables: { "output" => "result" })
      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(sub_mission).and_return(runner)
      allow(runner).to receive(:execute).and_return(completed_run)

      result = node.execute(context)

      expect(result).to be_success
      expect(result.output).to eq("result")
      expect(result.variables["output"]).to eq("result")
    end

    it "returns failure when sub-mission fails" do
      sub_mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })
      context.set_variable("_current_node_data", { "mission_id" => sub_mission.id.to_s })

      failed_run = instance_double(MissionRun, completed?: false, error: "Something went wrong")
      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(sub_mission).and_return(runner)
      allow(runner).to receive(:execute).and_return(failed_run)

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Something went wrong")
    end

    it "passes input variables as trigger_data to sub-mission" do
      sub_mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })
      context.set_variable("query", "test query")
      context.set_variable("_current_node_data", {
                             "mission_id" => sub_mission.id.to_s,
                             "input_variables" => { "q" => "{{query}}" },
                           })

      completed_run = instance_double(MissionRun, completed?: true, variables: { "output" => "ok" })
      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(sub_mission).and_return(runner)
      allow(runner).to receive(:execute) do |variables:, trigger_data:|
        expect(trigger_data["q"]).to eq("test query")
        expect(variables["_nesting_depth"]).to eq(1)
        completed_run
      end

      node.execute(context)
    end

    it "returns output variables from sub-mission output node" do
      sub_mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })
      context.set_variable("_current_node_data", { "mission_id" => sub_mission.id.to_s })

      completed_run = instance_double(MissionRun, completed?: true, variables: {
                                        "output" => { "description" => "A photo" },
                                        "_output_meta" => { "status" => "success", "status_code" => 200 },
                                        "response" => "A photo description",
                                        "_trigger_data" => {},
                                        "_nesting_depth" => 1,
                                      },)
      runner = instance_double(Missions::Runner)
      allow(Missions::Runner).to receive(:new).with(sub_mission).and_return(runner)
      allow(runner).to receive(:execute).and_return(completed_run)

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["response"]).to eq("A photo description")
    end

    it "catches unexpected errors" do
      sub_mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })
      context.set_variable("_current_node_data", { "mission_id" => sub_mission.id.to_s })

      allow(Missions::Runner).to receive(:new).and_raise(StandardError, "boom")

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Sub-mission error: boom")
    end
  end
end
