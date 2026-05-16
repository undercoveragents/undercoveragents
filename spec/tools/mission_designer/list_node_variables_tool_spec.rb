# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::ListNodeVariablesTool do
  let(:mission) { create(:mission) }
  let(:tool) { described_class.new(mission) }

  def runtime_context_for(target_mission)
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: nil,
      user: nil,
      tenant: target_mission.operation.tenant,
      operation: target_mission.operation,
    )
  end

  def llm_to_output_flow
    {
      "nodes" => [
        { "id" => "node-1", "type" => "llm", "position" => { "x" => 0, "y" => 0 },
          "data" => { "name" => "Summarizer", "prompt" => "Summarize" }, },
        { "id" => "node-2", "type" => "output", "position" => { "x" => 400, "y" => 0 },
          "data" => { "name" => "Output" }, },
      ],
      "edges" => [
        { "id" => "edge-1", "source" => "node-1", "sourceHandle" => "default", "target" => "node-2" },
      ],
    }
  end

  describe "#name" do
    it "returns list_node_variables" do
      expect(tool.name).to eq("list_node_variables")
    end
  end

  describe "#execute" do
    it "returns a clear message when mission context is missing" do
      tool_without_mission = described_class.new
      expected_message = [
        "Mission context is required before listing node variables.",
        "Create or open a mission first, or pass mission_id after creating a mission in the same turn.",
      ].join(" ")

      expect(tool_without_mission.execute(node_id: "node-1"))
        .to eq(expected_message)
    end

    it "reads another mission when mission_id is provided" do
      other_mission = create(:mission, operation: mission.operation)
      runtime_context = runtime_context_for(other_mission)
      target_tool = described_class.new(nil, runtime_context:)
      other_mission.update!(flow_data: llm_to_output_flow)

      result = target_tool.execute(node_id: "node-2", mission_id: other_mission.id)

      expect(result).to include("summarizer.response")
    end

    it "supports batched node lookups" do
      mission.update!(flow_data: llm_to_output_flow)

      result = tool.execute(node_ids: ["node-1", "node-2"])

      expect(result).to include("## Variables available at node `node-1`")
      expect(result).to include("## Variables available at node `node-2`")
      expect(result).to include("summarizer.response")
    end

    it "supports batched node lookups from a JSON array string" do
      mission.update!(flow_data: llm_to_output_flow)

      result = tool.execute(node_ids: '["node-1", "node-2"]')

      expect(result).to include("## Variables available at node `node-1`")
      expect(result).to include("## Variables available at node `node-2`")
    end

    it "asks for node ids when the input normalizes to nothing" do
      expect(tool.execute(node_ids: "   ")).to eq("Provide node_id or node_ids.")
    end

    it "returns builtin variables for empty flow" do
      result = tool.execute(node_id: "node-1")
      expect(result).to include("input")
      expect(result).not_to include("_current_node_data")
    end

    it "returns upstream variables for a connected node" do
      mission.update!(flow_data: llm_to_output_flow)

      result = tool.execute(node_id: "node-2")
      expect(result).to include(
        "Variables available at node",
        "do not guess alternate syntaxes",
        "Do not use temp_id values, raw node IDs, or guessed normalized labels",
        "wrap the identifier in `{{...}}`",
        "`selected_variables`, mission test expectations, collection refs, or formulas",
        "summarizer.response",
        "input",
      )
    end

    it "includes declared code output variables from upstream code nodes" do
      mission.update!(flow_data: {
                        "nodes" => [
                          { "id" => "node-1", "type" => "code", "position" => { "x" => 0, "y" => 0 },
                            "data" => {
                              "name" => "Transform",
                              "code" => "set('count', 2); 2",
                              "output_variables" => [{ "name" => "count", "description" => "Item count" }],
                            }, },
                          { "id" => "node-2", "type" => "output", "position" => { "x" => 400, "y" => 0 },
                            "data" => { "name" => "Output" }, },
                        ],
                        "edges" => [
                          { "id" => "edge-1", "source" => "node-1", "sourceHandle" => "default", "target" => "node-2" },
                        ],
                      })

      result = tool.execute(node_id: "node-2")

      expect(result).to include("transform.result")
      expect(result).to include("transform.count")
    end

    it "filters out internal variables prefixed with underscore" do
      mission.update!(flow_data: {
                        "nodes" => [
                          { "id" => "node-1", "type" => "llm", "position" => { "x" => 0, "y" => 0 },
                            "data" => { "name" => "LLM", "prompt" => "Hi" }, },
                          { "id" => "node-2", "type" => "output", "position" => { "x" => 400, "y" => 0 },
                            "data" => { "name" => "Output" }, },
                        ],
                        "edges" => [
                          { "id" => "edge-1", "source" => "node-1", "sourceHandle" => "default", "target" => "node-2" },
                        ],
                      })

      result = tool.execute(node_id: "node-2")
      expect(result).not_to include("_current_node_data")
    end

    it "includes global variables" do
      mission.update!(flow_data: {
                        "nodes" => [
                          { "id" => "node-1", "type" => "output", "position" => { "x" => 0, "y" => 0 },
                            "data" => { "name" => "Output" }, },
                        ],
                        "edges" => [],
                        "global_variables" => [
                          { "key" => "api_key", "value" => "secret", "type" => "string" },
                        ],
                      })

      result = tool.execute(node_id: "node-1")
      expect(result).to include("api_key")
    end

    it "adds iterator done-branch guidance when results are available" do
      mission.update!(flow_data: {
                        "nodes" => [
                          { "id" => "iter", "type" => "iterator", "position" => { "x" => 0, "y" => 0 },
                            "data" => { "name" => "My Iter", "collection" => "[1,2,3]" }, },
                          { "id" => "after", "type" => "output", "position" => { "x" => 400, "y" => 0 },
                            "data" => { "name" => "After" }, },
                        ],
                        "edges" => [
                          { "id" => "edge-1", "source" => "iter", "sourceHandle" => "done", "target" => "after" },
                        ],
                      })

      result = tool.execute(node_id: "after")

      expect(result).to include("my_iter.results")
      expect(result).to include("mission formulas only evaluate scalar numbers, strings, and booleans")
      expect(result).to include("inspect any `results` entry carefully before aggregating or comparing it")
    end

    it "returns error message on unexpected failure" do
      allow(Missions::VariableRegistry).to receive(:new).and_raise(StandardError, "boom")
      result = tool.execute(node_id: "node-1")
      expect(result).to include("Error listing variables")
      expect(result).to include("boom")
    end

    it "returns the empty-state message when no selectable variables are available" do
      registry = instance_double(Missions::VariableRegistry, available_at: [])
      allow(Missions::VariableRegistry).to receive(:new).and_return(registry)

      result = tool.execute(node_id: "node-1")

      expect(result).to eq("No variables available at node `node-1`.")
    end

    it "returns batched empty-state sections when allow_empty is true" do
      registry = instance_double(Missions::VariableRegistry, available_at: [])
      allow(Missions::VariableRegistry).to receive(:new).and_return(registry)

      result = tool.execute(node_ids: ["node-1", "node-2"])

      expect(result).to include("## Variables available at node `node-1` (0)")
      expect(result).to include("## Variables available at node `node-2` (0)")
    end
  end

  describe "private formatting helpers" do
    it "omits the description suffix when a variable has no description" do
      entry = instance_double(
        Missions::VariableRegistry::Entry,
        qualified_name: nil,
        name: "result",
        type: "string",
        description: nil,
      )

      expect(tool.send(:format_entry, entry)).to eq("- `result` (string)")
    end

    it "treats entries without a declared type as non-collection values" do
      entry = instance_double(Missions::VariableRegistry::Entry, type: nil)

      expect(tool.send(:collection_like_entry?, entry)).to be(false)
    end

    it "returns nil for non-array structured node id JSON" do
      expect(tool.send(:parse_structured_node_ids, '{"id":"node-1"}')).to be_nil
    end

    it "returns nil for invalid node id JSON" do
      expect(tool.send(:parse_structured_node_ids, "node-1,node-2")).to be_nil
    end
  end
end
