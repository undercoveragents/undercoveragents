# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::ApplyFlowPatchTool do
  let(:mission) { create(:mission) }
  let(:tool) { described_class.new(mission) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
  end

  def add_alias_edge_nodes
    tool.execute(patch: {
      add_nodes: [
        { temp_id: "input_node", type: "input" },
        { temp_id: "condition_node", type: "condition", label: "Gate", config: { expression: "true" } },
        { temp_id: "true_output", type: "output", label: "Yes" },
        { temp_id: "false_output", type: "output", label: "No" },
      ],
    }.to_json)

    mission.reload.flow_data["nodes"].index_by { |node| node.dig("data", "label") }
  end

  def alias_edge_entries(nodes_by_label)
    [
      {
        source_node_id: nodes_by_label.fetch("Input").fetch("id"),
        target_node_id: nodes_by_label.fetch("Gate").fetch("id"),
        port: "default",
      },
      {
        source_node_id: nodes_by_label.fetch("Gate").fetch("id"),
        target_node_id: nodes_by_label.fetch("Yes").fetch("id"),
        port: "true",
      },
      {
        source_node_id: nodes_by_label.fetch("Gate").fetch("id"),
        target_node_id: nodes_by_label.fetch("No").fetch("id"),
        port: "false",
      },
    ]
  end

  def template_to_output_patch
    {
      add_nodes: [
        { temp_id: "tpl", type: "text_template", name: "Greeting Builder", config: { template: "Hello" } },
        {
          temp_id: "out",
          type: "output",
          config: {
            response_body: "{{tpl.text}}",
            selected_variables: ["tpl.text"],
          },
          near_node_id: "tpl",
        },
      ],
      add_edges: [
        { source: "tpl", target: "out" },
      ],
    }.to_json
  end

  def set_variable_alias_patch
    {
      add_nodes: [
        {
          temp_id: "set",
          type: "set_variable",
          config: {
            variables: [
              { name: "status", value: "active", type: "string" },
            ],
          },
        },
      ],
    }.to_json
  end

  describe "#name" do
    it "returns apply_flow_patch" do
      expect(tool.name).to eq("apply_flow_patch")
    end
  end

  describe "#execute" do
    it "patches another mission in the same operation when mission_id is provided" do
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

      result = target_tool.execute(
        mission_id: other_mission.id,
        patch: { add_nodes: [{ temp_id: "in", type: "input" }] }.to_json,
      )

      expect(result).to include("Patch Applied", "Operations: 1", "Errors: 0")
      expect(other_mission.reload.flow_data["nodes"].size).to eq(1)
      expect(mission.reload.flow_data.to_h["nodes"].to_a).to be_empty
    end

    it "refuses to patch Headquarter missions" do
      headquarter_mission = create(:mission, operation: mission.operation.tenant.headquarter_operation)
      runtime_context = BuiltinTools::RuntimeContext::Context.new(
        agent: nil,
        chat: nil,
        mission: nil,
        ui_context: nil,
        user: create(:user, :admin, tenant: mission.operation.tenant),
        tenant: mission.operation.tenant,
        operation: mission.operation.tenant.headquarter_operation,
      )

      result = described_class.new(nil, runtime_context:).execute(
        mission_id: headquarter_mission.id,
        patch: { add_nodes: [{ temp_id: "in", type: "input" }] }.to_json,
      )

      expect(result).to eq("Error: #{ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE}")
      expect(headquarter_mission.reload.flow_data["nodes"]).to eq([])
    end

    it "adds nodes without a temp_id" do
      patch = { add_nodes: [{ type: "input" }] }.to_json
      result = tool.execute(patch:)
      expect(result).to include("Operations: 1", "Errors: 0")
      expect(result).not_to include("Assigned Node IDs")
    end

    it "rejects blank patches" do
      expect(tool.execute(patch: "")).to include("must not be blank")
    end

    it "rejects non-JSON-object input" do
      expect(tool.execute(patch: "[]")).to include("must be a JSON object")
    end

    it "reports JSON parse errors" do
      expect(tool.execute(patch: "{bogus")).to include("Invalid JSON patch")
    end

    it "adds nodes and wires edges using temp_id references" do
      patch = {
        add_nodes: [
          { temp_id: "in", type: "input" },
          { temp_id: "out", type: "output", near_node_id: "in" },
        ],
        add_edges: [
          { source: "in", target: "out" },
        ],
      }.to_json

      result = tool.execute(patch:)
      expect(result).to include("Patch Applied", "Operations: 3", "Errors: 0", "Assigned Node IDs")
      expect(result).to include("var_prefix")
      expect(mission.reload.flow_data["nodes"].size).to eq(2)
      expect(mission.flow_data["edges"].size).to eq(1)
    end

    it "normalizes same-patch temp_id variable references to the actual var_prefix" do
      result = tool.execute(patch: template_to_output_patch)
      output_node = mission.reload.flow_data["nodes"].find { |node| node["type"] == "output" }

      expect(output_node.dig("data", "response_body")).to eq("{{greeting_builder.text}}")
      expect(output_node.dig("data", "selected_variables")).to eq(["greeting_builder.text"])
      expect(result).to include("## Normalized Variable References")
      expect(result).to include("`tpl`")
    end

    it "normalizes set_variable variables-array aliases into assignments" do
      tool.execute(patch: set_variable_alias_patch)
      node = mission.reload.flow_data["nodes"].first

      expect(node.dig("data", "assignments")).to eq({ "status" => "active" })
      expect(node.dig("data", "variables")).to be_nil
    end

    it "accepts hash-style references for node placement and edge endpoints" do
      patch = {
        add_nodes: [
          { temp_id: "in", type: "input" },
          { temp_id: "out", type: "output", near_node_id: { ref: "in" } },
        ],
        add_edges: [
          { source: { ref: "in" }, target: { ref: "out" } },
        ],
      }.to_json

      result = tool.execute(patch:)

      expect(result).to include("Patch Applied", "Operations: 3", "Errors: 0")
      expect(mission.reload.flow_data["edges"].size).to eq(1)
    end

    it "reports a clear error when a multi-port source edge omits source_port" do
      patch = {
        add_nodes: [
          { temp_id: "in", type: "input" },
          { temp_id: "api", type: "http_request", config: { url: "https://example.com", method: "GET" } },
          { temp_id: "out", type: "output" },
        ],
        add_edges: [
          { source: "in", target: "api" },
          { source: "api", target: "out" },
        ],
      }.to_json

      result = tool.execute(patch:)

      expect(result).to include("Errors: 1")
      expect(result).to include("Source port is required")
      expect(result).to include("success, error")
    end

    it "updates and removes nodes in one call" do
      patch_add = { add_nodes: [{ temp_id: "n", type: "input", name: "Start" }] }.to_json
      tool.execute(patch: patch_add)
      node_id = mission.reload.flow_data["nodes"].first["id"]

      patch = {
        update_nodes: [{ id: node_id, name: "Kickoff" }],
        remove_nodes: [node_id],
      }.to_json

      result = tool.execute(patch:)
      expect(result).to include("Operations: 2", "Errors: 0")
      expect(mission.reload.flow_data["nodes"]).to be_empty
    end

    it "supports update entries with id, name, and config" do
      node_id = Missions::FlowEditor.new(mission).add_node(
        type: "llm",
        name: "Draft Prompt",
        config: { "prompt" => "Before" },
      )[:node][:id]

      patch = {
        update_nodes: [{ id: node_id, name: "Render HTML", config: { prompt: "After" } }],
      }.to_json

      result = tool.execute(patch:)
      node = mission.reload.flow_data["nodes"].find { |entry| entry["id"] == node_id }

      expect(result).to include("Operations: 1", "Errors: 0")
      expect(node.dig("data", "label")).to eq("Render HTML")
      expect(node.dig("data", "prompt")).to eq("After")
    end

    it "reports a clear error when update_nodes entries omit an id" do
      result = tool.execute(patch: { update_nodes: [{ config: { prompt: "After" } }] }.to_json)
      expect(result).to include("update_node: missing `id`")
    end

    it "reports a clear error when update_nodes entries are not objects" do
      result = tool.execute(patch: { update_nodes: ["not-an-object"] }.to_json)
      expect(result).to include("update_node: missing `id`")
    end

    it "removes edges via remove_edges" do
      setup_patch = {
        add_nodes: [
          { temp_id: "a", type: "input" },
          { temp_id: "b", type: "output", near_node_id: "a" },
        ],
        add_edges: [{ source: "a", target: "b" }],
      }.to_json
      tool.execute(patch: setup_patch)
      edge_id = mission.reload.flow_data["edges"].first["id"]

      result = tool.execute(patch: { remove_edges: [{ edge_id: }] }.to_json)
      expect(result).to include("Operations: 1")
      expect(mission.reload.flow_data["edges"]).to be_empty
    end

    it "accepts read_flow-style edge aliases and raw edge IDs" do
      nodes_by_label = add_alias_edge_nodes
      result = tool.execute(patch: { add_edges: alias_edge_entries(nodes_by_label) }.to_json)

      edges = mission.reload.flow_data["edges"]

      expect(result).to include("Operations: 3", "Errors: 0")
      expect(edges.pluck("sourceHandle")).to contain_exactly("default", "true", "false")

      remove_result = tool.execute(patch: { remove_edges: edges.pluck("id") }.to_json)

      expect(remove_result).to include("Operations: 3", "Errors: 0")
      expect(mission.reload.flow_data["edges"]).to be_empty
    end

    it "accepts common node ID and label aliases" do
      result = tool.execute(patch: {
        add_nodes: [{ ref: "input_node", node_type: "input", label: "Inbound" }],
      }.to_json)

      node = mission.reload.flow_data["nodes"].first
      node_id = node.fetch("id")

      expect(result).to include("Operations: 1", "Errors: 0")
      expect(node.dig("data", "label")).to eq("Inbound")

      update_result = tool.execute(patch: {
        update_nodes: [{ node_id:, label: "Renamed Input" }],
        remove_nodes: [{ node_id: }],
      }.to_json)

      expect(update_result).to include("Operations: 2", "Errors: 0")
      expect(mission.reload.flow_data["nodes"]).to be_empty
    end

    it "CRUDs global variables" do
      add_patch = { add_globals: [{ key: "threshold", value: "0.8", type: "number" }] }.to_json
      expect(tool.execute(patch: add_patch)).to include("Operations: 1")

      update_patch = { update_globals: [{ key: "threshold", value: "0.9" }] }.to_json
      expect(tool.execute(patch: update_patch)).to include("Operations: 1")

      remove_patch = { remove_globals: ["threshold"] }.to_json
      expect(tool.execute(patch: remove_patch)).to include("Operations: 1")
      expect(mission.reload.flow_data["global_variables"].to_a).to eq([])
    end

    it "collects per-operation errors without aborting the batch" do
      patch = {
        add_nodes: [{ temp_id: "bad", type: "nonexistent" }],
        update_nodes: [{ id: "node-missing", config: { label: "x" } }],
        remove_nodes: ["node-also-missing"],
        remove_edges: [{ edge_id: "edge-missing" }],
      }.to_json

      result = tool.execute(patch:)
      expect(result).to include("Errors: 4", "Unknown node type", "Node not found", "No matching edge found")
    end

    it "collects errors for edge and global operations" do
      patch = {
        add_nodes: [{ type: "nonexistent" }],
        add_edges: [{ source: "missing-a", target: "missing-b" }],
        add_globals: [{ key: "", value: "x" }],
        update_globals: [{ key: "unknown-global", value: "y" }],
        remove_globals: [{ key: "also-unknown" }],
      }.to_json

      result = tool.execute(patch:)
      expect(result).to include("Errors: 5", "add_edge", "add_global", "update_global", "remove_global")
    end

    it "reports validation issues after applying a patch" do
      patch = {
        add_nodes: [{ temp_id: "l", type: "llm", name: "Lonely", config: { llm_config_source: "node" } }],
      }.to_json
      result = tool.execute(patch:)
      expect(result).to include("Validation Issues")
    end

    it "reports valid flow when result passes validation" do
      fake_result = instance_double(
        Missions::FlowValidator::Result,
        valid?: true,
        node_count: 2,
        edge_count: 1,
        warnings: [],
      )
      allow(Missions::FlowValidator).to receive(:call).and_return(fake_result)

      patch = { add_nodes: [{ temp_id: "i", type: "input" }] }.to_json
      result = tool.execute(patch:)

      expect(result).to include("Flow is valid")
      expect(result).to include("already includes validation")
    end

    it "includes validation warnings even when the flow is otherwise valid" do
      fake_result = instance_double(
        Missions::FlowValidator::Result,
        valid?: true,
        node_count: 2,
        edge_count: 1,
        warnings: ['Node "Filter" (filter) has unconnected ports: no_match'],
      )
      allow(Missions::FlowValidator).to receive(:call).and_return(fake_result)

      patch = { add_nodes: [{ temp_id: "i", type: "input" }] }.to_json
      result = tool.execute(patch:)

      expect(result).to include("Flow is valid")
      expect(result).to include("## Warnings")
      expect(result).to include("unconnected ports: no_match")
      expect(result).not_to include("already includes validation")
    end

    it "broadcasts an arrange event after applying changes" do
      tool.execute(patch: { add_nodes: [{ temp_id: "i", type: "input" }] }.to_json)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
        .with("mission_flow_#{mission.id}", hash_including(html: include("data-arrange")))
    end

    it "skips the arrange broadcast when no operations ran" do
      tool.execute(patch: "{}")
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_append_to)
        .with(anything, hash_including(html: include("data-arrange")))
    end

    it "swallows arrange broadcast failures" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to).and_raise(StandardError, "chan-down")
      allow(Rails.logger).to receive(:warn)
      result = tool.execute(patch: { add_nodes: [{ temp_id: "i", type: "input" }] }.to_json)
      expect(result).to include("Patch Applied")
      expect(Rails.logger).to have_received(:warn).with(/arrange broadcast failed/)
    end

    it "rescues unexpected tool-level failures" do
      allow(Missions::FlowEditor).to receive(:new).and_raise(StandardError, "boom")
      expect(tool.execute(patch: "{}")).to include("Error applying patch", "boom")
    end

    it "passes remove_nodes entries that use hash form" do
      tool.execute(patch: { add_nodes: [{ temp_id: "n", type: "input" }] }.to_json)
      node_id = mission.reload.flow_data["nodes"].first["id"]
      result = tool.execute(patch: { remove_nodes: [{ id: node_id }] }.to_json)
      expect(result).to include("Operations: 1")
    end
  end

  describe "private formatting helpers" do
    it "omits the var_prefix suffix when a node mapping has no variable name" do
      parts = []

      tool.send(:append_temp_ids, parts, { "temp-node" => "node-1" }, { "node-1" => {} })

      expect(parts).to include("## Assigned Node IDs")
      expect(parts).to include("- `temp-node` → `node-1`")
      expect(parts.join("\n")).not_to include("var_prefix")
    end
  end

  describe "private normalization helpers" do
    it "leaves set_variable configs unchanged when alias extraction is blank" do
      config = { "variables" => "not-json" }

      expect(tool.send(:normalize_set_variable_config, "set_variable", config)).to eq(config)
    end

    it "leaves non set_variable configs unchanged" do
      config = { "variables" => { "status" => "active" } }

      expect(tool.send(:normalize_set_variable_config, "input", config)).to eq(config)
    end

    it "leaves set_variable configs unchanged when assignments are already present" do
      config = { "assignments" => { "status" => "active" } }

      expect(tool.send(:normalize_set_variable_config, "set_variable", config)).to eq(config)
    end

    it "extracts assignment aliases from hash, string, and values payloads" do
      hash_aliases = tool.send(:extract_assignment_aliases, { "variables" => { status: "active" } })
      string_aliases = tool.send(:extract_assignment_aliases, { "variables" => '[{"name":"total","expression":"1"}]' })
      values_aliases = tool.send(:extract_assignment_aliases, { "values" => { status: "active" } })

      expect(hash_aliases).to eq({ "status" => "active" })
      expect(string_aliases).to eq({ "total" => "1" })
      expect(values_aliases).to eq({ "status" => "active" })
    end

    it "returns an empty hash when assignment aliases are absent or invalid" do
      expect(tool.send(:extract_assignment_aliases, { "variables" => "not-json" })).to eq({})
      expect(tool.send(:extract_assignment_aliases, { "other" => "value" })).to eq({})
    end

    it "skips non-hash and blank array alias entries" do
      aliases = tool.send(
        :extract_assignment_aliases_from_array,
        ["skip", { "name" => "", "value" => "x" }, { "name" => "status", "value" => "active" }],
      )

      expect(aliases).to eq({ "status" => "active" })
    end

    it "reconciles added node configs when later temp-id mappings change them" do
      state = tool.send(:build_state, mission)
      state.editor = instance_spy(Missions::FlowEditor)
      state.temp_variables["tpl"] = "greeting_builder"
      state.added_node_entries << {
        node_id: "node-1",
        node_type: "output",
        raw_config: { "response_body" => "{{tpl.text}}" },
        applied_config: { "response_body" => "{{tpl.text}}" },
      }

      tool.send(:reconcile_added_node_configs, state)

      expect(state.editor).to have_received(:update_node).with(
        node_id: "node-1",
        data: { "response_body" => "{{greeting_builder.text}}" },
      )
      expect(state.added_node_entries.first[:applied_config]).to eq({ "response_body" => "{{greeting_builder.text}}" })
    end

    it "rewrites temp variable aliases across nested hashes and arrays" do
      state = tool.send(:build_state, mission)
      state.temp_variables["tpl"] = "greeting_builder"

      rewritten = tool.send(:rewrite_temp_variable_aliases, state, {
                              "response_body" => "{{tpl.text}}",
                              "selected_variables" => ["tpl.text"],
                              "meta" => { "count" => 1 },
                            })

      expect(rewritten).to eq(
        {
          "response_body" => "{{greeting_builder.text}}",
          "selected_variables" => ["greeting_builder.text"],
          "meta" => { "count" => 1 },
        },
      )
      expect(state.rewritten_temp_ids).to eq([["tpl", "greeting_builder"]])
    end

    it "leaves unmatched temp variable strings unchanged" do
      state = tool.send(:build_state, mission)
      state.temp_variables["tpl"] = "tpl"

      expect(tool.send(:rewrite_temp_variable_aliases_in_string, state, "tpl.text")).to eq("tpl.text")
      expect(state.rewritten_temp_ids).to be_empty
    end

    it "does not record temp variables when the added node has no variable name" do
      state = tool.send(:build_state, mission)

      tool.send(:remember_temp_node, state, "tpl", { id: "node-1", variable_name: nil })

      expect(state.temp_ids).to eq({ "tpl" => "node-1" })
      expect(state.temp_variables).to be_empty
    end
  end
end
