# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::ValidateFlowTool do
  let(:mission) { create(:mission) }
  let(:tool) { described_class.new(mission) }
  let(:editor) { Missions::FlowEditor.new(mission) }

  def recovery_hint_result # rubocop:disable Metrics/MethodLength
    Struct.new(:valid?, :node_count, :edge_count, :config_errors, :structural_issues, :warnings).new(
      false,
      1,
      0,
      {
        "n1" => [
          {
            node_name: "Output",
            node_type: "output",
            field: "variables",
            message: "references unknown variable {{temp_result.body}}",
          },
          {
            node_name: "Store",
            node_type: "set_variable",
            field: "assignments",
            message: "final_summary is also defined as a blank global variable. " \
                     "Globals are seeded inputs only; remove the blank global or give it a real value.",
          },
        ],
      },
      [],
      [],
    )
  end

  describe "#name" do
    it "returns validate_flow" do
      expect(tool.name).to eq("validate_flow")
    end
  end

  describe "#execute" do
    it "validates another mission when mission_id is provided" do
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
      Missions::FlowEditor.new(other_mission).add_node(type: "input", name: "Kickoff")

      result = target_tool.execute(mission_id: other_mission.id)

      expect(result).to include("1 nodes")
    end

    context "when flow is valid" do
      it "reports valid with counts" do
        result = tool.execute
        expect(result).to include("valid")
        expect(result).to include("0 nodes")
      end
    end

    context "when flow has configuration errors" do
      it "formats config errors section" do
        editor.add_node(type: "llm", name: "No Config", config: { "llm_config_source" => "node" })

        result = tool.execute
        expect(result).to include("Configuration Errors")
        expect(result).to include("connector_id")
        expect(result).to include("errors that should be fixed")
      end

      it "adds targeted recovery hints for variable, global, and set_variable issues" do
        allow(Missions::FlowValidator).to receive(:call).and_return(recovery_hint_result)

        output = tool.execute

        expect(output).to include("## Recovery Hints")
        expect(output).to include("call `list_node_variables`")
        expect(output).to include("Do not use temp_id")
        expect(output).to include("Globals are seeded inputs/constants only")
        expect(output).to include("`set_variable` expects `assignments`")
      end

      it "uses node_id as label when node_name is nil" do
        result = Struct.new(:valid?, :node_count, :edge_count, :config_errors, :structural_issues, :warnings).new(
          false,
          1,
          0,
          {
            "n-bare" => [
              { node_name: nil, node_type: "llm", field: "connector_id", message: "is required" },
            ],
          },
          [],
          [],
        )

        allow(Missions::FlowValidator).to receive(:call).and_return(result)

        result = tool.execute
        expect(result).to include("Configuration Errors")
        expect(result).to include("**n-bare**: connector_id is required")
      end

      it "formats the node name and type when they are available" do
        result = Struct.new(:valid?, :node_count, :edge_count, :config_errors, :structural_issues, :warnings).new(
          false,
          1,
          0,
          {
            "n1" => [
              { node_name: "Planner", node_type: "llm", field: "connector_id", message: "is required" },
            ],
          },
          [],
          [],
        )

        allow(Missions::FlowValidator).to receive(:call).and_return(result)

        expect(tool.execute).to include("**Planner (llm)**: connector_id is required")
      end
    end

    context "when flow has structural issues" do
      it "formats structural issues section" do
        editor.add_node(type: "llm", name: "Orphan 1",
                        config: { "connector_id" => "1", "model" => "gpt-4.1" },)
        editor.add_node(type: "llm", name: "Orphan 2",
                        config: { "connector_id" => "1", "model" => "gpt-4.1" },)

        result = tool.execute
        expect(result).to include("Structural Issues")
        expect(result).to include("no outgoing connections")
      end
    end

    context "when flow has warnings" do
      it "formats warnings section" do
        n1 = editor.add_node(type: "condition", name: "Check", config: { "expression" => "x > 5" })
        n2 = editor.add_node(type: "llm", name: "True Path",
                             config: { "connector_id" => "1", "model" => "gpt-4.1" },)
        editor.add_edge(source_node_id: n1[:node][:id], target_node_id: n2[:node][:id], source_port: "true")

        result = tool.execute
        expect(result).to include("Warnings")
        expect(result).to include("unconnected ports")
      end
    end

    it "returns error message on unexpected failure" do
      allow(Missions::FlowValidator).to receive(:call).and_raise(StandardError, "boom")
      result = tool.execute
      expect(result).to include("Error validating flow")
      expect(result).to include("boom")
    end
  end
end
