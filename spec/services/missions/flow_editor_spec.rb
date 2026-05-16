# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::FlowEditor do
  let(:mission) { create(:mission) }
  let(:editor) { described_class.new(mission) }

  describe "#read_flow" do
    it "returns empty flow for new mission" do
      result = editor.read_flow
      expect(result[:nodes]).to be_empty
      expect(result[:edges]).to be_empty
      expect(result[:validation_errors]).to be_a(Hash)
    end

    it "returns nodes and edges from existing flow" do
      mission.update!(flow_data: {
                        "nodes" => [
                          { "id" => "node-1", "type" => "llm", "position" => { "x" => 100, "y" => 200 },
                            "data" => { "name" => "My LLM", "prompt" => "Hello" }, },
                        ],
                        "edges" => [
                          { "id" => "edge-1", "source" => "node-1", "sourceHandle" => "default", "target" => "node-2" },
                        ],
                      })

      result = editor.read_flow
      expect(result[:nodes].size).to eq(1)
      expect(result[:nodes].first[:id]).to eq("node-1")
      expect(result[:nodes].first[:type]).to eq("llm")
      expect(result[:nodes].first[:name]).to eq("My LLM")
      expect(result[:edges].size).to eq(1)
    end

    it "surfaces unique variable prefixes when multiple node labels repeat" do
      mission.update!(flow_data: {
                        "nodes" => [
                          { "id" => "node-1", "type" => "json_extract", "position" => { "x" => 0, "y" => 0 },
                            "data" => { "label" => "JSON Extract" }, },
                          { "id" => "node-2", "type" => "json_extract", "position" => { "x" => 300, "y" => 0 },
                            "data" => { "label" => "JSON Extract" }, },
                        ],
                        "edges" => [],
                      })

      result = editor.read_flow

      expect(result[:nodes].pluck(:variable_name)).to eq(["json_extract", "json_extract_2"])
    end

    it "keeps malformed nodes without a data payload unchanged during normalization" do
      normalized = Missions::FlowPersistenceNormalizer.normalize_node({ "id" => "node-1", "type" => "llm" })

      expect(normalized["data"]).to be_nil
    end

    it "derives a variable-safe name from the label when normalizing a node" do
      normalized = Missions::FlowPersistenceNormalizer.normalize_node(
        {
          "id" => "node-1",
          "type" => "llm",
          "data" => { "label" => "Read Data" },
        },
      )

      expect(normalized.dig("data", "name")).to eq("read_data")
    end

    it "leaves the derived name unset when both name and label are blank" do
      normalized = Missions::FlowPersistenceNormalizer.normalize_node(
        {
          "id" => "node-1",
          "type" => "llm",
          "data" => { "label" => " ", "name" => nil },
        },
      )

      expect(normalized.dig("data", "name")).to be_nil
    end
  end

  describe "private layout helpers" do
    it "uses explicit node widths when auto-placing new nodes" do
      flow = {
        "nodes" => [
          { "id" => "node-1", "type" => "llm", "position" => { "x" => 100, "y" => 200 },
            "style" => { "width" => 400 }, },
        ],
        "edges" => [],
      }

      expect(editor.send(:auto_x, flow)).to eq(580.0)
    end

    it "ignores malformed positions and widths when auto-placing new nodes" do
      flow = {
        "nodes" => [
          { "id" => "node-1", "type" => "llm", "position" => { "x" => nil, "y" => 200 },
            "style" => { "width" => 500 }, },
          { "id" => "node-2", "type" => "llm", "position" => { "x" => 100, "y" => 220 },
            "style" => { "width" => "wide" }, },
        ],
        "edges" => [],
      }

      expect(editor.send(:auto_x, flow)).to eq(440.0)
    end

    it "uses the first valid y position when earlier nodes are malformed" do
      flow = {
        "nodes" => [
          { "id" => "node-1", "type" => "llm", "position" => { "x" => 100, "y" => nil } },
          { "id" => "node-2", "type" => "llm", "position" => { "x" => 180, "y" => 220 } },
        ],
        "edges" => [],
      }

      expect(editor.send(:auto_y, flow)).to eq(220.0)
    end

    it "skips nodes without a position hash when deriving auto layout" do
      flow = {
        "nodes" => [
          { "id" => "node-1", "type" => "llm", "position" => "broken" },
          { "id" => "node-2", "type" => "llm", "position" => { "x" => 180, "y" => 260 } },
        ],
        "edges" => [],
      }

      expect(editor.send(:auto_y, flow)).to eq(260.0)
    end

    it "returns nil when summarize_persisted_node cannot find the node" do
      expect(editor.send(:summarize_persisted_node, "missing-node")).to be_nil
    end
  end

  describe "#add_node" do
    it "adds a valid node and returns it" do
      result = editor.add_node(type: "llm", name: "Test LLM")
      expect(result[:error]).to be_nil
      expect(result[:node][:type]).to eq("llm")
      expect(result[:node][:name]).to eq("Test LLM")
      expect(result[:node][:id]).to start_with("node-")

      expect(mission.reload.flow_data["nodes"].size).to eq(1)
    end

    it "adds node with config" do
      result = editor.add_node(type: "llm", config: { "prompt" => "Hello", "connector_id" => "1" })
      node = result[:node]
      expect(node[:config]).to include("prompt" => "Hello", "connector_id" => "1")
    end

    it "defaults omitted llm connection settings to system preference while preserving thinking options" do
      create(:system_preference, :configured, tenant: mission.operation.tenant, model_id: "deepseek-v4-flash")

      result = editor.add_node(
        type: "llm",
        config: {
          "prompt" => "Hello",
          "thinking_effort" => "high",
          "thinking_budget" => 256,
        },
      )
      node = result[:node]

      expect(node[:config]["llm_config_source"]).to eq("system_preference")
      expect(node[:config]).not_to include("connector_id")
      expect(node[:config]).not_to include("model")
      expect(node[:config]["thinking_effort"]).to eq("high")
      expect(node[:config]["thinking_budget"]).to eq(256)
    end

    it "preserves explicit llm connector and model when defaults are configured" do
      create(:system_preference, :configured, tenant: mission.operation.tenant, model_id: "deepseek-v4-flash")

      result = editor.add_node(
        type: "llm",
        config: { "prompt" => "Hello", "connector_id" => "manual-connector", "model" => "manual-model" },
      )
      node = result[:node]

      expect(node[:config]["connector_id"]).to eq("manual-connector")
      expect(node[:config]["model"]).to eq("manual-model")
    end

    it "returns a suffixed variable prefix when adding duplicate labels" do
      first = editor.add_node(type: "json_extract", name: "JSON Extract")
      second = editor.add_node(type: "json_extract", name: "JSON Extract")

      expect(first.dig(:node, :variable_name)).to eq("json_extract")
      expect(second.dig(:node, :variable_name)).to eq("json_extract_2")
    end

    it "returns error for unknown type" do
      result = editor.add_node(type: "nonexistent")
      expect(result[:error]).to match(/Unknown node type/)
    end

    it "prevents duplicate singleton nodes" do
      editor.add_node(type: "input")
      result = editor.add_node(type: "input")
      expect(result[:error]).to match(/only one/i)
    end

    it "auto-positions nodes" do
      editor.add_node(type: "llm")
      result = editor.add_node(type: "condition")
      node = result[:node]
      expect(node[:position]["x"]).to be > 250
    end

    it "positions node near referenced node when near_node_id is given" do
      first = editor.add_node(type: "llm", name: "First")
      first_id = first[:node][:id]

      result = editor.add_node(type: "condition", name: "Second", near_node_id: first_id)
      node = result[:node]
      first_x = first[:node][:position]["x"]
      first_y = first[:node][:position]["y"]

      expect(node[:position]["x"]).to eq(first_x + 300.0)
      expect(node[:position]["y"]).to eq(first_y)
    end

    it "falls back to auto position when near_node_id is not found" do
      result = editor.add_node(type: "llm", name: "Alone", near_node_id: "nonexistent")
      expect(result[:node]).to be_present
      expect(result[:node][:position]["x"]).to be_a(Numeric)
    end

    it "falls back to auto position when near node has malformed coordinates" do
      mission.update!(flow_data: {
                        "nodes" => [
                          { "id" => "node-1", "type" => "llm", "position" => { "x" => nil, "y" => 300 },
                            "data" => { "name" => "Broken" }, },
                        ],
                        "edges" => [],
                      })

      result = editor.add_node(type: "condition", name: "Second", near_node_id: "node-1")

      expect(result[:node][:position]["x"]).to eq(250.0)
      expect(result[:node][:position]["y"]).to eq(150.0)
    end

    it "pushes undo snapshot" do
      editor.add_node(type: "llm")
      expect(mission.reload.can_undo?).to be true
    end
  end

  describe "#update_node" do
    let!(:node_id) do
      result = editor.add_node(type: "llm", name: "Original")
      result[:node][:id]
    end

    it "updates node data" do
      result = editor.update_node(node_id:, data: { "prompt" => "Updated prompt" })
      expect(result[:error]).to be_nil
      expect(result[:node][:config]).to include("prompt" => "Updated prompt")
    end

    it "merges with existing data" do
      editor.update_node(node_id:, data: { "prompt" => "First" })
      editor.update_node(node_id:, data: { "connector_id" => "5" })

      flow = mission.reload.flow_data
      node_data = flow["nodes"].first["data"]
      expect(node_data).to include("prompt" => "First", "connector_id" => "5")
    end

    it "returns error for unknown node" do
      result = editor.update_node(node_id: "nonexistent", data: { "prompt" => "test" })
      expect(result[:error]).to match(/Node not found/)
    end

    it "derives variable name from label when name is blank" do
      editor.update_node(node_id:, data: { "name" => "", "label" => "My Derived Label" })

      saved_node = mission.reload.flow_data["nodes"].find { |n| n["id"] == node_id }
      expect(saved_node["data"]["name"]).to eq("my_derived_label")
    end
  end

  describe "#remove_node" do
    it "removes node and connected edges" do
      r1 = editor.add_node(type: "llm", name: "First")
      r2 = editor.add_node(type: "condition", name: "Second")
      n1_id = r1[:node][:id]
      n2_id = r2[:node][:id]

      editor.add_edge(source_node_id: n1_id, target_node_id: n2_id)

      result = editor.remove_node(node_id: n1_id)
      expect(result[:error]).to be_nil
      expect(result[:removed_edges_count]).to eq(1)

      flow = mission.reload.flow_data
      expect(flow["nodes"].size).to eq(1)
      expect(flow["edges"]).to be_empty
    end

    it "returns error for unknown node" do
      result = editor.remove_node(node_id: "nonexistent")
      expect(result[:error]).to match(/Node not found/)
    end
  end

  describe "#add_edge" do
    let!(:node1_id) { editor.add_node(type: "llm")[:node][:id] }
    let!(:node2_id) { editor.add_node(type: "condition")[:node][:id] }

    it "connects two nodes" do
      result = editor.add_edge(source_node_id: node1_id, target_node_id: node2_id)
      expect(result[:error]).to be_nil
      expect(result[:edge][:source]).to eq(node1_id)
      expect(result[:edge][:target]).to eq(node2_id)
      expect(result[:edge][:source_port]).to eq("default")
    end

    it "supports custom source port" do
      result = editor.add_edge(source_node_id: node2_id, target_node_id: node1_id, source_port: "true")
      expect(result[:edge][:source_port]).to eq("true")
    end

    it "rejects missing source_port for multi-port source nodes" do
      result = editor.add_edge(source_node_id: node2_id, target_node_id: node1_id)

      expect(result[:error]).to match(/Source port is required/)
      expect(result[:error]).to include("true, false")
    end

    it "rejects invalid source_port values for multi-port source nodes" do
      api_id = editor.add_node(
        type: "http_request",
        config: { "url" => "https://example.com", "method" => "GET" },
      )[:node][:id]
      out_id = editor.add_node(type: "output")[:node][:id]

      result = editor.add_edge(source_node_id: api_id, target_node_id: out_id, source_port: "default")

      expect(result[:error]).to match(/Invalid source port `default`/)
      expect(result[:error]).to include("success, error")
    end

    it "returns an error when the source node exposes no output ports" do
      mission.update!(flow_data: {
                        "nodes" => [
                          { "id" => "source", "type" => "mystery", "data" => { "label" => "Mystery" } },
                          { "id" => "target", "type" => "output", "data" => { "label" => "Output" } },
                        ],
                        "edges" => [],
                      })

      result = editor.add_edge(source_node_id: "source", target_node_id: "target")

      expect(result[:error]).to include("Mystery")
      expect(result[:error]).to include("has no output ports")
    end

    it "persists custom edge metadata for non-default ports" do
      editor.add_edge(source_node_id: node2_id, target_node_id: node1_id, source_port: "false")

      edge = mission.reload.flow_data["edges"].first
      expect(edge["type"]).to eq("custom")
      expect(edge.dig("markerEnd", "type")).to eq("arrowclosed")
      expect(edge.dig("data", "label")).to eq("false")
    end

    it "prevents duplicate edges" do
      editor.add_edge(source_node_id: node1_id, target_node_id: node2_id)
      result = editor.add_edge(source_node_id: node1_id, target_node_id: node2_id)
      expect(result[:error]).to match(/already exists/)
    end

    it "returns error for nonexistent source" do
      result = editor.add_edge(source_node_id: "bad", target_node_id: node2_id)
      expect(result[:error]).to match(/Source node not found/)
    end

    it "returns error for nonexistent target" do
      result = editor.add_edge(source_node_id: node1_id, target_node_id: "bad")
      expect(result[:error]).to match(/Target node not found/)
    end

    it "prevents self-loops" do
      result = editor.add_edge(source_node_id: node1_id, target_node_id: node1_id)
      expect(result[:error]).to match(/Cannot connect a node to itself/)
    end

    it "rejects reconnecting a loop body back into its own loop node" do
      seed_id = editor.add_node(type: "input")[:node][:id]
      loop_id = editor.add_node(type: "loop", config: { "max_iterations" => 3 })[:node][:id]
      body_id = editor.add_node(type: "delay", config: { "duration" => 1, "unit" => "seconds" })[:node][:id]

      editor.add_edge(source_node_id: seed_id, target_node_id: loop_id)
      editor.add_edge(source_node_id: loop_id, target_node_id: body_id, source_port: "loop")

      result = editor.add_edge(source_node_id: body_id, target_node_id: loop_id)

      expect(result[:error]).to match(/cannot receive an incoming edge from its own body/i)
    end
  end

  describe "#remove_edge" do
    let!(:node1_id) { editor.add_node(type: "llm")[:node][:id] }
    let!(:node2_id) { editor.add_node(type: "condition")[:node][:id] }

    before do
      editor.add_edge(source_node_id: node1_id, target_node_id: node2_id)
    end

    it "removes edge by source and target" do
      result = editor.remove_edge(source_node_id: node1_id, target_node_id: node2_id)
      expect(result[:error]).to be_nil
      expect(result[:removed_edges].size).to eq(1)
      expect(mission.reload.flow_data["edges"]).to be_empty
    end

    it "removes edge by id" do
      edge_id = mission.reload.flow_data["edges"].first["id"]
      result = editor.remove_edge(edge_id:)
      expect(result[:error]).to be_nil
    end

    it "returns error when no matching edge" do
      result = editor.remove_edge(source_node_id: "bad", target_node_id: "bad")
      expect(result[:error]).to match(/No matching edge/)
    end
  end

  describe "#list_global_variables" do
    it "returns empty array for new mission" do
      expect(editor.list_global_variables).to eq([])
    end

    it "returns defined global variables" do
      editor.add_global_variable(key: "api_key", value: "secret", type: "string")
      vars = editor.list_global_variables
      expect(vars.size).to eq(1)
      expect(vars.first["key"]).to eq("api_key")
    end
  end

  describe "#add_global_variable" do
    it "adds a variable and returns it" do
      result = editor.add_global_variable(key: "threshold", value: "0.8", type: "number")
      expect(result[:variable]["key"]).to eq("threshold")
      expect(result[:variable]["value"]).to eq("0.8")
      expect(result[:variable]["type"]).to eq("number")
      expect(mission.reload.flow_data["global_variables"].size).to eq(1)
    end

    it "defaults type to string" do
      result = editor.add_global_variable(key: "name", value: "test")
      expect(result[:variable]["type"]).to eq("string")
    end

    it "casts boolean values" do
      result = editor.add_global_variable(key: "flag", value: "true", type: "boolean")
      expect(result[:variable]["type"]).to eq("boolean")
      expect(result[:variable]["value"]).to eq("true")
    end

    it "casts integer number values" do
      result = editor.add_global_variable(key: "count", value: "42", type: "number")
      expect(result[:variable]["value"]).to eq("42")
    end

    it "returns error for blank key" do
      result = editor.add_global_variable(key: "")
      expect(result[:error]).to match(/Key is required/)
    end

    it "returns error for invalid type" do
      result = editor.add_global_variable(key: "x", type: "array")
      expect(result[:error]).to match(/Invalid type/)
    end

    it "rejects duplicate keys" do
      editor.add_global_variable(key: "threshold", value: "1")
      result = editor.add_global_variable(key: "threshold", value: "2")
      expect(result[:error]).to match(/already exists/)
    end
  end

  describe "#update_global_variable" do
    before do
      editor.add_global_variable(key: "threshold", value: "0.8", type: "number")
    end

    it "updates value only" do
      result = editor.update_global_variable(key: "threshold", value: "0.9")
      expect(result[:variable]["value"]).to eq("0.9")
      expect(result[:variable]["type"]).to eq("number")
    end

    it "updates type without changing value when value is omitted" do
      result = editor.update_global_variable(key: "threshold", type: "boolean")

      expect(result[:variable]["type"]).to eq("boolean")
      expect(result[:variable]["value"]).to eq("0.8")
    end

    it "updates type and value" do
      result = editor.update_global_variable(key: "threshold", value: "true", type: "boolean")
      expect(result[:variable]["type"]).to eq("boolean")
      expect(result[:variable]["value"]).to eq("true")
    end

    it "returns error for missing key" do
      result = editor.update_global_variable(key: "")
      expect(result[:error]).to match(/Key is required/)
    end

    it "returns error for not found key" do
      result = editor.update_global_variable(key: "missing", value: "x")
      expect(result[:error]).to match(/not found/)
    end

    it "returns error for invalid type" do
      result = editor.update_global_variable(key: "threshold", type: "array")
      expect(result[:error]).to match(/Invalid type/)
    end
  end

  describe "#remove_global_variable" do
    before do
      editor.add_global_variable(key: "to_delete", value: "x")
    end

    it "removes existing variable" do
      result = editor.remove_global_variable(key: "to_delete")
      expect(result[:removed_variable]["key"]).to eq("to_delete")
      expect(mission.reload.flow_data["global_variables"] || []).to be_empty
    end

    it "returns error for blank key" do
      result = editor.remove_global_variable(key: "")
      expect(result[:error]).to match(/Key is required/)
    end

    it "returns error for missing variable" do
      result = editor.remove_global_variable(key: "missing")
      expect(result[:error]).to match(/not found/)
    end
  end

  describe "broadcasting" do
    it "broadcasts flow update via Turbo Streams on add_node" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)

      editor.add_node(type: "llm")

      expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
        "mission_flow_#{mission.id}",
        target: "mission-flow-updates",
        html: "<div data-refresh=\"true\"></div>",
      )
    end

    it "logs a warning when broadcasting fails" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to).and_raise(StandardError, "Cable disconnected")
      allow(Rails.logger).to receive(:warn)

      expect { editor.add_node(type: "llm") }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/FlowEditor broadcast failed: Cable disconnected/)
    end

    it "does not broadcast on read-only operations" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)

      editor.read_flow
      editor.list_global_variables

      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_append_to)
    end
  end
end
