# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::ReadFlowTool do
  let(:mission) { create(:mission) }
  let(:tool) { described_class.new(mission) }

  def write_flow(nodes:, edges: [], global_variables: nil)
    data = { "nodes" => nodes, "edges" => edges }
    data["global_variables"] = global_variables if global_variables
    mission.update!(flow_data: data)
  end

  describe "#name" do
    it "returns read_mission_flow" do
      expect(tool.name).to eq("read_mission_flow")
    end
  end

  describe "#execute" do
    it "reads another mission when mission_id is provided" do
      other_mission = create(:mission, operation: mission.operation)
      runtime_context = BuiltinTools::RuntimeContext::Context.new(
        agent: nil,
        chat: nil,
        mission: nil,
        ui_context: nil,
        user: nil,
        tenant: mission.operation.tenant,
        operation: mission.operation,
      )
      target_tool = described_class.new(nil, runtime_context:)
      Missions::FlowEditor.new(other_mission).add_node(type: "input", name: "Imported Start")

      result = target_tool.execute(mission_id: other_mission.id)

      expect(result).to include("Imported Start")
      expect(result).not_to include("No nodes yet.")
    end

    it "returns empty flow for new mission" do
      result = tool.execute
      expect(result).to include("Nodes (0)", "No nodes yet.")
    end

    it "returns a resolver error when no mission context is available" do
      result = described_class.new(nil).execute

      expect(result).to include("Error reading flow", "No mission is available")
    end

    it "renders a compact summary by default" do
      write_flow(
        nodes: [
          { "id" => "node-1", "type" => "llm", "position" => { "x" => 100, "y" => 200 },
            "data" => { "name" => "My LLM", "prompt" => "Hello" }, },
          { "id" => "node-2", "type" => "condition", "position" => { "x" => 400, "y" => 200 },
            "data" => { "name" => "Check", "expression" => "x > 5" }, },
        ],
        edges: [
          { "id" => "edge-1", "source" => "node-1", "sourceHandle" => "default", "target" => "node-2" },
        ],
      )

      result = tool.execute
      expect(result).to include("Nodes (2)", "My LLM", "node-1", "Edges (1)")
      expect(result).not_to include("var_prefix=")
    end

    it "returns error message on unexpected failure" do
      allow(Missions::FlowEditor).to receive(:new).and_raise(StandardError, "boom")
      result = tool.execute
      expect(result).to include("Error reading flow", "boom")
    end

    it "summarises global variables in compact mode (keys only)" do
      write_flow(
        nodes: [],
        global_variables: [
          { "key" => "api_key", "value" => "secret", "type" => "string" },
          { "key" => "threshold", "value" => "0.8", "type" => "number" },
        ],
      )

      result = tool.execute
      expect(result).to include("Global Variables (2)", "api_key", "threshold")
      expect(result).not_to include("secret")
    end

    it "shows global variable values and types in full mode" do
      write_flow(
        nodes: [],
        global_variables: [{ "key" => "threshold", "value" => "0.8", "type" => "number" }],
      )

      result = tool.execute(detail: "full")
      expect(result).to include("threshold", "0.8", "type: number")
    end

    it "omits global variables section when none defined" do
      expect(tool.execute).not_to include("Global Variables")
    end

    it "truncates long config values in full mode" do
      long_prompt = "x" * 100
      write_flow(
        nodes: [
          { "id" => "node-1", "type" => "llm", "position" => { "x" => 100, "y" => 200 },
            "data" => { "name" => "My LLM", "prompt" => long_prompt }, },
        ],
      )

      expect(tool.execute(detail: "full")).to include("...")
    end

    it "includes the variable prefix when expanded" do
      write_flow(
        nodes: [
          { "id" => "node-1", "type" => "llm", "position" => { "x" => 100, "y" => 200 },
            "data" => { "label" => "My LLM", "name" => "my_llm" }, },
        ],
      )

      expect(tool.execute(detail: "full")).to include("var_prefix=`my_llm`")
    end

    it "shows suffixed prefixes when duplicate labels repeat" do
      write_flow(
        nodes: [
          { "id" => "node-1", "type" => "json_extract", "position" => { "x" => 0, "y" => 0 },
            "data" => { "label" => "JSON Extract" }, },
          { "id" => "node-2", "type" => "json_extract", "position" => { "x" => 0, "y" => 0 },
            "data" => { "label" => "JSON Extract" }, },
        ],
      )

      result = tool.execute(detail: "full")
      expect(result).to include("var_prefix=`json_extract`")
      expect(result).to include("var_prefix=`json_extract_2`")
    end

    it "omits the variable prefix when an expanded node does not expose one" do
      allow(Missions::FlowEditor).to receive(:new).and_return(
        instance_double(
          Missions::FlowEditor,
          read_flow: {
            nodes: [{ id: "node-1", type: "input", name: "Start", variable_name: nil, config: {} }],
            edges: [],
            global_variables: [],
            validation_errors: {},
          },
        ),
      )

      expect(tool.execute(detail: "full")).not_to include("var_prefix=")
    end

    it "only expands requested node_ids in partial mode" do
      write_flow(
        nodes: [
          { "id" => "node-1", "type" => "llm", "position" => { "x" => 0, "y" => 0 },
            "data" => { "label" => "Alpha", "prompt" => "alpha-prompt" }, },
          { "id" => "node-2", "type" => "llm", "position" => { "x" => 0, "y" => 0 },
            "data" => { "label" => "Beta", "prompt" => "beta-prompt" }, },
        ],
      )

      result = tool.execute(node_ids: "node-1")
      expect(result).to include("prompt=alpha-prompt")
      expect(result).not_to include("prompt=beta-prompt")
    end

    it "reports no connections when edges are empty" do
      write_flow(nodes: [])
      expect(tool.execute).to include("No connections yet.")
    end

    it "surfaces validation errors when present" do
      allow(Missions::NodeConfigValidator).to receive(:validate_flow).and_return(
        "node-1" => [{ node_name: "X", node_type: "llm", field: "model", message: "is required" }],
      )

      write_flow(
        nodes: [
          { "id" => "node-1", "type" => "llm", "position" => { "x" => 0, "y" => 0 },
            "data" => { "label" => "X" }, },
        ],
      )

      result = tool.execute
      expect(result).to include("Validation Errors", "is required", "field: model")
    end

    it "includes an empty compact summary when node config is blank" do
      write_flow(
        nodes: [
          { "id" => "node-1", "type" => "input", "position" => { "x" => 0, "y" => 0 },
            "data" => { "label" => "Start" }, },
        ],
      )

      result = tool.execute
      expect(result).to include("node-1", "input", "Start")
    end
  end
end
