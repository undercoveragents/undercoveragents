# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::FlowValidator do
  let(:mission) { create(:mission) }
  let(:editor) { Missions::FlowEditor.new(mission) }

  def add_flow_node(editor, type:, name:, config: {})
    editor.add_node(type:, name:, config:).dig(:node, :id)
  end

  def connect_flow_nodes(editor, edges)
    edges.each do |source_node_id, target_node_id, source_port|
      editor.add_edge(source_node_id:, target_node_id:, source_port:)
    end
  end

  def loop_body_reentry_flow
    {
      "nodes" => [
        { "id" => "input", "type" => "input", "data" => { "label" => "Input" } },
        { "id" => "loop", "type" => "loop",
          "data" => { "label" => "Repeat Delay", "max_iterations" => 5 }, },
        { "id" => "delay", "type" => "delay",
          "data" => { "label" => "Wait 1 Second", "duration" => 1, "unit" => "seconds" }, },
        { "id" => "output", "type" => "output", "data" => { "label" => "Output" } },
      ],
      "edges" => [
        { "id" => "e1", "source" => "input", "target" => "loop", "sourceHandle" => "default" },
        { "id" => "e2", "source" => "loop", "target" => "delay", "sourceHandle" => "loop" },
        { "id" => "e3", "source" => "delay", "target" => "loop", "sourceHandle" => "default" },
        { "id" => "e4", "source" => "loop", "target" => "output", "sourceHandle" => "done" },
      ],
    }
  end

  def loop_body_join_flow
    {
      "nodes" => [
        { "id" => "input", "type" => "input", "data" => { "label" => "Input" } },
        { "id" => "iter", "type" => "iterator",
          "data" => { "label" => "Each", "collection" => "items" }, },
        { "id" => "body", "type" => "text_template",
          "data" => { "label" => "Per Item", "template" => "{{item}}" }, },
        { "id" => "join", "type" => "set_variable",
          "data" => { "label" => "Shared Join", "assignments" => { "value" => "1" } }, },
      ],
      "edges" => [
        { "id" => "e1", "source" => "input", "target" => "iter", "sourceHandle" => "default" },
        { "id" => "e2", "source" => "iter", "target" => "body", "sourceHandle" => "loop" },
        { "id" => "e3", "source" => "body", "target" => "join", "sourceHandle" => "default" },
        { "id" => "e4", "source" => "iter", "target" => "join", "sourceHandle" => "done" },
      ],
    }
  end

  def invalid_source_port_flow
    JSON.parse(<<~JSON)
      {
        "nodes": [
          {"id": "input", "type": "input", "data": {"label": "Input"}},
          {"id": "http", "type": "http_request", "data": {"label": "HTTP Request", "url": "https://example.com", "method": "GET"}},
          {"id": "llm", "type": "llm", "data": {"label": "Generate Text", "prompt": "Summarize", "connector_id": "1", "model": "gpt-4.1"}},
          {"id": "out", "type": "output", "data": {"label": "Output", "response_body": "{{generate_text.response}}"}}
        ],
        "edges": [
          {"id": "edge-1", "source": "input", "target": "http", "sourceHandle": "default"},
          {"id": "edge-2", "source": "http", "target": "llm", "sourceHandle": "default"},
          {"id": "edge-3", "source": "llm", "target": "out", "sourceHandle": "default"}
        ]
      }
    JSON
  end

  describe ".call" do
    context "with empty flow" do
      it "returns valid result" do
        result = described_class.call(mission)

        expect(result).to be_valid
        expect(result.config_errors).to be_empty
        expect(result.structural_issues).to be_empty
        expect(result.warnings).to be_empty
      end

      it "reports node and edge counts" do
        result = described_class.call(mission)

        expect(result.node_count).to eq(0)
        expect(result.edge_count).to eq(0)
      end
    end

    context "with valid flow" do
      it "returns valid when nodes are properly connected" do
        n1 = editor.add_node(type: "llm", name: "Step 1",
                             config: { "connector_id" => "1", "model" => "gpt-4.1" },)
        n2 = editor.add_node(type: "output", name: "Done")
        editor.add_edge(source_node_id: n1[:node][:id], target_node_id: n2[:node][:id])

        result = described_class.call(mission)

        expect(result).to be_valid
        expect(result.node_count).to eq(2)
        expect(result.edge_count).to eq(1)
      end
    end

    context "with configuration errors" do
      it "reports missing required fields" do
        editor.add_node(type: "llm", name: "No Config", config: { "llm_config_source" => "node" })

        result = described_class.call(mission)

        expect(result).not_to be_valid
        expect(result.config_errors).not_to be_empty
        expect(result.config_errors.values.flatten.pluck(:field)).to include("connector_id")
      end

      it "rejects blank globals that shadow workflow-computed outputs" do
        node = editor.add_node(type: "set_variable", name: "Set Final Summary",
                               config: { "assignments" => { "final_summary" => "'PASS'" } },)
        output = editor.add_node(type: "output", name: "Done")
        editor.add_edge(source_node_id: node[:node][:id], target_node_id: output[:node][:id])
        mission.update!(flow_data: mission.flow_data.merge(
          "global_variables" => [{ "key" => "final_summary", "value" => "", "type" => "string" }],
        ))

        result = described_class.call(mission)

        expect(result).not_to be_valid
        expect(result.config_errors.values.flatten).to include(
          a_hash_including(field: "assignments", message: /blank global variable/i),
        )
      end

      it "rejects formulas that use array outputs directly" do
        iterator = editor.add_node(type: "iterator", name: "Iterate Numbers",
                                   config: { "collection" => "[1, 2, 3]" },)
        condition = editor.add_node(type: "condition", name: "Check Results",
                                    config: { "expression" => "iterate_numbers.results == 2" },)
        output = editor.add_node(type: "output", name: "Done")
        editor.add_edge(source_node_id: iterator[:node][:id], target_node_id: condition[:node][:id],
                        source_port: "done",)
        editor.add_edge(source_node_id: condition[:node][:id], target_node_id: output[:node][:id],
                        source_port: "true",)

        result = described_class.call(mission)

        expect(result).not_to be_valid
        expect(result.config_errors.values.flatten).to include(
          a_hash_including(field: "expression", message: /iterate_numbers\.results/),
        )
      end
    end

    context "with structural issues" do
      it "reports disconnected nodes" do
        editor.add_node(type: "llm", name: "Orphan 1",
                        config: { "connector_id" => "1", "model" => "gpt-4.1" },)
        editor.add_node(type: "llm", name: "Orphan 2",
                        config: { "connector_id" => "1", "model" => "gpt-4.1" },)

        result = described_class.call(mission)

        expect(result).not_to be_valid
        expect(result.structural_issues).to include(a_string_matching(/no outgoing connections/))
      end

      it "reports dangling edges referencing missing source nodes" do
        node_data = { "label" => "X", "connector_id" => "1", "model" => "gpt-4.1" }
        mission.update!(flow_data: {
                          "nodes" => [{ "id" => "n1", "type" => "llm", "data" => node_data }],
                          "edges" => [{ "id" => "e1", "source" => "n-gone", "target" => "n1",
                                        "sourceHandle" => "default", }],
                        })

        result = described_class.call(mission)

        expect(result).not_to be_valid
        expect(result.structural_issues).to include(a_string_matching(/missing source node/))
      end

      it "reports dangling edges referencing missing nodes" do
        node_data = { "label" => "X", "connector_id" => "1", "model" => "gpt-4.1" }
        mission.update!(flow_data: {
                          "nodes" => [{ "id" => "n1", "type" => "llm", "data" => node_data }],
                          "edges" => [{ "id" => "e1", "source" => "n1", "target" => "n-gone",
                                        "sourceHandle" => "default", }],
                        })

        result = described_class.call(mission)

        expect(result).not_to be_valid
        expect(result.structural_issues).to include(a_string_matching(/missing target node/))
      end

      it "reports loop bodies reconnecting into their own loop node" do
        mission.update!(flow_data: loop_body_reentry_flow)

        result = described_class.call(mission)

        expect(result).not_to be_valid
        expect(result.config_errors.values.flatten).to include(
          a_hash_including(field: "edges", message: /cannot receive an incoming edge from its own body/i),
        )
      end

      it "reports nodes that join loop-body inputs with outside inputs" do
        mission.update!(flow_data: loop_body_join_flow)

        result = described_class.call(mission)

        expect(result).not_to be_valid
        expect(result.config_errors.values.flatten).to include(
          a_hash_including(field: "edges", message: %r{mixes inputs from inside and outside loop/iterator body}i),
        )
      end
    end

    context "with warnings" do
      it "warns about missing condition ports" do
        n1 = editor.add_node(type: "condition", name: "Check", config: { "expression" => "x > 5" })
        n2 = editor.add_node(type: "llm", name: "True Path",
                             config: { "connector_id" => "1", "model" => "gpt-4.1" },)
        editor.add_edge(source_node_id: n1[:node][:id], target_node_id: n2[:node][:id], source_port: "true")

        result = described_class.call(mission)

        expect(result.warnings).to include(a_string_matching(/unconnected ports.*false/))
      end

      it "warns about missing iterator ports" do
        n1 = editor.add_node(type: "iterator", name: "Each", config: { "collection" => "items" })
        n2 = editor.add_node(type: "llm", name: "Process",
                             config: { "connector_id" => "1", "model" => "gpt-4.1" },)
        editor.add_edge(source_node_id: n1[:node][:id], target_node_id: n2[:node][:id], source_port: "loop")

        result = described_class.call(mission)

        expect(result.warnings).to include(a_string_matching(/unconnected ports.*done/))
      end

      it "does not warn about missing done for a nested inner loop with no post-loop continuation" do
        seed = editor.add_node(type: "set_variable", name: "Seed",
                               config: { "assignments" => { "counter" => "0" } },)
        outer = editor.add_node(type: "loop", name: "Outer", config: { "max_iterations" => "3" })
        inner = editor.add_node(type: "loop", name: "Inner", config: { "max_iterations" => "3" })
        body = editor.add_node(type: "set_variable", name: "Increment",
                               config: { "assignments" => { "counter" => "counter + 1" } },)
        output = editor.add_node(type: "output", name: "Done")

        editor.add_edge(source_node_id: seed[:node][:id], target_node_id: outer[:node][:id])
        editor.add_edge(source_node_id: outer[:node][:id], target_node_id: inner[:node][:id], source_port: "loop")
        editor.add_edge(source_node_id: inner[:node][:id], target_node_id: body[:node][:id], source_port: "loop")
        editor.add_edge(source_node_id: outer[:node][:id], target_node_id: output[:node][:id], source_port: "done")

        result = described_class.call(mission)

        expect(result.warnings).not_to include(a_string_matching(/Inner.*unconnected ports.*done/))
      end

      it "warns about missing filter ports" do
        n1 = editor.add_node(type: "filter", name: "Filter",
                             config: { "collection" => "items", "expression" => "item > 0" },)
        n2 = editor.add_node(type: "llm", name: "Matched",
                             config: { "connector_id" => "1", "model" => "gpt-4.1" },)
        editor.add_edge(source_node_id: n1[:node][:id], target_node_id: n2[:node][:id], source_port: "match")

        result = described_class.call(mission)

        expect(result.warnings).to include(a_string_matching(/unconnected ports.*no_match/))
      end

      it "does not report loop-body leaf nodes as missing outgoing connections" do
        seed = editor.add_node(type: "set_variable", name: "Seed",
                               config: { "assignments" => { "items" => "[1, 2]" } },)
        iterator = editor.add_node(type: "iterator", name: "Each",
                                   config: { "collection" => "items" },)
        leaf = editor.add_node(type: "text_template", name: "Trace",
                               config: { "template" => "value={{item}}" },)

        editor.add_edge(source_node_id: seed[:node][:id], target_node_id: iterator[:node][:id])
        editor.add_edge(source_node_id: iterator[:node][:id], target_node_id: leaf[:node][:id], source_port: "loop")

        result = described_class.call(mission)

        expect(result.structural_issues).not_to include(a_string_matching(/Trace.*no outgoing connections/))
      end

      it "does not report recursive loop-body leaf nodes as missing outgoing connections" do
        seed = editor.add_node(type: "set_variable", name: "Seed",
                               config: { "assignments" => { "items" => "[1, 2]" } },)
        iterator = editor.add_node(type: "iterator", name: "Each",
                                   config: { "collection" => "items" },)
        intermediate = editor.add_node(type: "set_variable", name: "Prepare",
                                       config: { "assignments" => { "value" => "item" } },)
        leaf = editor.add_node(type: "text_template", name: "Trace",
                               config: { "template" => "value={{value}}" },)

        editor.add_edge(source_node_id: seed[:node][:id], target_node_id: iterator[:node][:id])
        editor.add_edge(
          source_node_id: iterator[:node][:id],
          target_node_id: intermediate[:node][:id],
          source_port: "loop",
        )
        editor.add_edge(source_node_id: intermediate[:node][:id], target_node_id: leaf[:node][:id])

        result = described_class.call(mission)

        expect(result.structural_issues).not_to include(a_string_matching(/Trace.*no outgoing connections/))
      end

      it "does not report cached loop-body ancestry as missing outgoing connections" do
        seed = add_flow_node(editor, type: "set_variable", name: "Seed",
                                     config: { "assignments" => { "items" => "[1, 2]" } },)
        iterator = add_flow_node(editor, type: "iterator", name: "Each", config: { "collection" => "items" })
        shared = add_flow_node(editor, type: "set_variable", name: "Shared",
                                       config: { "assignments" => { "value" => "item" } },)
        branch_a = add_flow_node(editor, type: "text_template", name: "Branch A",
                                         config: { "template" => "a={{value}}" },)
        branch_b = add_flow_node(editor, type: "text_template", name: "Branch B",
                                         config: { "template" => "b={{value}}" },)
        leaf = add_flow_node(editor, type: "text_template", name: "Trace",
                                     config: { "template" => "value={{value}}" },)

        connect_flow_nodes(
          editor,
          [[seed, iterator], [iterator, shared, "loop"], [shared, branch_a],
           [shared, branch_b], [branch_a, leaf], [branch_b, leaf],],
        )

        result = described_class.call(mission)

        expect(result.structural_issues).not_to include(a_string_matching(/Trace.*no outgoing connections/))
      end

      it "warns about missing http_request ports" do
        n1 = editor.add_node(type: "http_request", name: "API Call",
                             config: { "url" => "https://example.com", "method" => "GET" },)
        n2 = editor.add_node(type: "llm", name: "Success",
                             config: { "connector_id" => "1", "model" => "gpt-4.1" },)
        editor.add_edge(source_node_id: n1[:node][:id], target_node_id: n2[:node][:id], source_port: "success")

        result = described_class.call(mission)

        expect(result.warnings).to include(a_string_matching(/unconnected ports.*error/))
      end

      it "flags invalid source ports and warns when they disconnect downstream input" do
        mission.update!(flow_data: invalid_source_port_flow)

        result = described_class.call(mission)

        expect(result.structural_issues).to include(
          a_string_matching(/edge-2.*invalid source port `default`.*HTTP Request.*success, error/i),
        )
        expect(result.warnings).to include(
          a_string_matching(/Generate Text.*no valid incoming connections.*effectively disconnected/i),
        )
        expect(result.warnings).to include(a_string_matching(/HTTP Request.*unconnected ports: success, error/))
      end

      it "allows implicit joins fed by mutually exclusive downstream branches" do
        cond = editor.add_node(type: "condition", name: "Check", config: { "expression" => "x > 5" })
        true_path = editor.add_node(type: "set_variable", name: "True Path",
                                    config: { "assignments" => { "branch" => "TRUE" } },)
        false_path = editor.add_node(type: "set_variable", name: "False Path",
                                     config: { "assignments" => { "branch" => "FALSE" } },)
        join = editor.add_node(type: "text_template", name: "Shared Step",
                               config: { "template" => "{{branch}}" },)

        editor.add_edge(source_node_id: cond[:node][:id], target_node_id: true_path[:node][:id], source_port: "true")
        editor.add_edge(source_node_id: cond[:node][:id], target_node_id: false_path[:node][:id], source_port: "false")
        editor.add_edge(source_node_id: true_path[:node][:id], target_node_id: join[:node][:id])
        editor.add_edge(source_node_id: false_path[:node][:id], target_node_id: join[:node][:id])

        result = described_class.call(mission)

        expect(result.structural_issues.grep(/waits for all incoming predecessors/)).to be_empty
      end

      it "does not flag direct competing ports from one branch node to a shared continuation" do
        cond = editor.add_node(type: "condition", name: "Check", config: { "expression" => "x > 5" })
        output = editor.add_node(type: "output", name: "Out")

        editor.add_edge(source_node_id: cond[:node][:id], target_node_id: output[:node][:id], source_port: "true")
        editor.add_edge(source_node_id: cond[:node][:id], target_node_id: output[:node][:id], source_port: "false")

        result = described_class.call(mission)

        expect(result.structural_issues.grep(/waits for all incoming predecessors/)).to be_empty
      end

      it "allows joins fed by only some direct branch outcomes" do
        cond = editor.add_node(type: "condition", name: "Check", config: { "expression" => "x > 5" })
        independent = editor.add_node(type: "set_variable", name: "Normalize Sum",
                                      config: { "assignments" => { "value" => "1" } },)
        failure = editor.add_node(type: "output", name: "Failure")
        join = editor.add_node(type: "set_variable", name: "Build Success Report",
                               config: { "assignments" => { "report" => "'ok'" } },)

        editor.add_edge(source_node_id: cond[:node][:id], target_node_id: join[:node][:id], source_port: "true")
        editor.add_edge(source_node_id: cond[:node][:id], target_node_id: failure[:node][:id], source_port: "false")
        editor.add_edge(source_node_id: independent[:node][:id], target_node_id: join[:node][:id])

        result = described_class.call(mission)

        expect(result.structural_issues.grep(/waits for all incoming predecessors/)).to be_empty
      end

      it "allows joins when every direct branch outcome reaches the shared continuation" do
        cond = editor.add_node(type: "condition", name: "Check", config: { "expression" => "x > 5" })
        independent = editor.add_node(type: "set_variable", name: "Normalize Sum",
                                      config: { "assignments" => { "value" => "1" } },)
        join = editor.add_node(type: "set_variable", name: "Build Success Report",
                               config: { "assignments" => { "report" => "'ok'" } },)

        editor.add_edge(source_node_id: cond[:node][:id], target_node_id: join[:node][:id], source_port: "true")
        editor.add_edge(source_node_id: cond[:node][:id], target_node_id: join[:node][:id], source_port: "false")
        editor.add_edge(source_node_id: independent[:node][:id], target_node_id: join[:node][:id])

        result = described_class.call(mission)

        expect(result.structural_issues.grep(/direct branching predecessor only feeds it on some outcomes/)).to be_empty
      end

      it "does not flag implicit joins fed by independent predecessors" do
        left = editor.add_node(type: "set_variable", name: "Left",
                               config: { "assignments" => { "left" => "1" } },)
        right = editor.add_node(type: "set_variable", name: "Right",
                                config: { "assignments" => { "right" => "2" } },)
        output = editor.add_node(type: "output", name: "Out")

        editor.add_edge(source_node_id: left[:node][:id], target_node_id: output[:node][:id])
        editor.add_edge(source_node_id: right[:node][:id], target_node_id: output[:node][:id])

        result = described_class.call(mission)

        expect(result.structural_issues.grep(/waits for all incoming predecessors/)).to be_empty
      end

      it "warns when no starting node exists" do
        node_a = { "label" => "A", "connector_id" => "1", "model" => "gpt-4.1" }
        node_b = { "label" => "B", "connector_id" => "1", "model" => "gpt-4.1" }
        mission.update!(flow_data: {
                          "nodes" => [
                            { "id" => "n1", "type" => "llm", "data" => node_a },
                            { "id" => "n2", "type" => "llm", "data" => node_b },
                          ],
                          "edges" => [
                            { "id" => "e1", "source" => "n1", "target" => "n2", "sourceHandle" => "default" },
                            { "id" => "e2", "source" => "n2", "target" => "n1", "sourceHandle" => "default" },
                          ],
                        })

        result = described_class.call(mission)

        expect(result.warnings).to include(a_string_matching(/No starting node/))
      end
    end

    describe "global variable warnings" do
      it "warns about duplicate global variable keys" do
        mission.update!(flow_data: {
                          "nodes" => [],
                          "edges" => [],
                          "global_variables" => [
                            { "key" => "api_key", "value" => "a", "type" => "string" },
                            { "key" => "api_key", "value" => "b", "type" => "string" },
                          ],
                        })
        result = described_class.call(mission)
        expect(result.warnings).to include(a_string_matching(/Duplicate global variable key.*api_key/))
      end

      it "warns about blank values" do
        mission.update!(flow_data: {
                          "nodes" => [],
                          "edges" => [],
                          "global_variables" => [
                            { "key" => "empty_var", "value" => "", "type" => "string" },
                          ],
                        })
        result = described_class.call(mission)
        expect(result.warnings).to include(a_string_matching(/Global variable.*empty_var.*no value/))
      end

      it "warns about invalid types" do
        mission.update!(flow_data: {
                          "nodes" => [],
                          "edges" => [],
                          "global_variables" => [
                            { "key" => "bad_type", "value" => "x", "type" => "array" },
                          ],
                        })
        result = described_class.call(mission)
        expect(result.warnings).to include(a_string_matching(/Global variable.*bad_type.*invalid type/))
      end
    end

    describe "check_unconnected_ports with all ports connected" do
      it "does not warn when all ports are connected" do
        n1 = editor.add_node(type: "condition", name: "Check", config: { "expression" => "x > 5" })
        n2 = editor.add_node(type: "output", name: "True Out")
        n3 = editor.add_node(type: "output", name: "False Out")
        editor.add_edge(source_node_id: n1[:node][:id], target_node_id: n2[:node][:id], source_port: "true")
        editor.add_edge(source_node_id: n1[:node][:id], target_node_id: n3[:node][:id], source_port: "false")

        result = described_class.call(mission)

        port_warnings = result.warnings.select { |w| w.include?("unconnected ports") }
        expect(port_warnings).to be_empty
      end
    end

    describe "config errors include node metadata" do
      it "populates node_name and node_type when node exists" do
        mission.update!(flow_data: {
                          "nodes" => [
                            {
                              "id" => "n1",
                              "type" => "llm",
                              "data" => { "label" => "My LLM", "llm_config_source" => "node" },
                            },
                          ],
                          "edges" => [],
                        })

        result = described_class.call(mission)

        expect(result.config_errors).not_to be_empty
        err = result.config_errors["n1"].first
        expect(err[:node_name]).to eq("My LLM")
        expect(err[:node_type]).to eq("llm")
      end

      it "keeps node metadata nil when the validator reports an unknown node" do
        allow(Missions::NodeConfigValidator).to receive(:validate_flow).and_return(
          "missing-node" => [{ field: "connector_id", message: "is required" }],
        )

        result = described_class.call(mission)

        expect(result.config_errors["missing-node"]).to eq([
                                                             {
                                                               node_name: nil,
                                                               node_type: nil,
                                                               field: "connector_id",
                                                               message: "is required",
                                                             },
                                                           ])
      end
    end

    describe "private helper coverage" do
      it "returns output ports for switch nodes backed by a hash" do
        ports = described_class.new(mission).send(
          :output_port_keys,
          { type: "switch", data: { "cases" => { "premium" => "premium" } } },
        )

        expect(ports).to contain_exactly("premium", "default")
      end

      it "returns output ports for switch nodes backed by JSON case data" do
        ports = described_class.new(mission).send(
          :output_port_keys,
          { type: "switch", data: { "cases" => '{"premium":"premium","basic":"basic"}' } },
        )

        expect(ports).to contain_exactly("premium", "basic", "default")
      end

      it "returns the configured port map for non-switch branching nodes" do
        ports = described_class.new(mission).send(
          :output_port_keys,
          { type: "condition", data: {} },
        )

        expect(ports).to contain_exactly("true", "false")
      end

      it "returns no ports for unknown node types" do
        ports = described_class.new(mission).send(
          :output_port_keys,
          { type: "unknown_type", data: {} },
        )

        expect(ports).to eq([])
      end

      it "returns only the default switch port for invalid or unsupported case data", :aggregate_failures do
        validator = described_class.new(mission)

        expect(validator.send(:output_port_keys, { type: "switch", data: { "cases" => "{bad-json}" } }))
          .to eq(["default"])
        expect(validator.send(:output_port_keys, { type: "switch", data: { "cases" => 123 } }))
          .to eq(["default"])
      end

      it "keeps synthetic done omissions unchanged for non-looping node types" do
        validator = described_class.new(mission)
        context = { nested_loop_body_cache: {}, edges_by_target: {}, node_map: {} }

        result = validator.send(
          :filter_optional_nested_done_ports,
          { id: "cond-1", type: "condition" },
          ["done"],
          context,
        )

        expect(result).to eq(["done"])
      end

      it "returns cached nested loop-body membership when available" do
        validator = described_class.new(mission)
        context = {
          nested_loop_body_cache: { "inner-loop" => true },
          edges_by_target: {},
          node_map: {},
        }

        expect(validator.send(:nested_loop_body_member?, "inner-loop", context)).to be(true)
      end
    end
  end
end
