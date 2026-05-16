# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::VariableRegistry do
  def build_flow(nodes:, edges: [])
    { "nodes" => nodes, "edges" => edges }
  end

  def node(id, type, label: nil, data: {})
    { "id" => id, "type" => type, "data" => { "label" => label || type.titleize }.merge(data) }
  end

  def edge(source, target, port: "default")
    { "id" => "e-#{source}-#{target}", "source" => source, "target" => target, "sourceHandle" => port }
  end

  def register_dynamic_blank_name_node
    stub_const("Missions::Nodes::DynamicBlankName", Class.new do
      include MissionNodePlugin

      def self.node_type = "dynamic_blank_name"
      def self.node_label = "Dynamic Blank Name"
      def self.node_icon = "fa-solid fa-circle"
      def self.node_color = "#000000"
      def self.node_category = :node
      def self.node_description = "Test node"

      def self.variable_schema
        Missions::VariableSchema.new(outputs: [{ name: "*", type: :any, description: "Dynamic outputs" }])
      end

      def self.dynamic_output_variables(_node_data)
        [
          { name: "", description: "Ignore me" },
          { name: "value", description: "Keep me" },
        ]
      end
    end,)

    MissionNodePlugin.register_from_class(Missions::Nodes::DynamicBlankName)
  end

  describe "#all_variables" do
    it "includes built-in variables" do
      registry = described_class.new(build_flow(nodes: []))
      names = registry.all_variables.map(&:name)
      expect(names).to include("input")
      expect(names).not_to include("_current_node_data", "user_message")
    end

    it "collects output variables from all nodes" do
      flow = build_flow(
        nodes: [
          node("n1", "input", label: "Start", data: { "fields" => [{ "variable_name" => "query" }] }),
          node("n2", "llm", label: "Summarizer"),
        ],
        edges: [edge("n1", "n2")],
      )
      registry = described_class.new(flow)
      names = registry.all_variables.map(&:name)
      expect(names).to include("query", "response")
    end

    it "skips fields with blank variable_name" do
      flow = build_flow(
        nodes: [
          node("n1", "input", label: "Start",
                              data: { "fields" => [{ "variable_name" => "" }, { "variable_name" => "q" }] },),
        ],
      )
      registry = described_class.new(flow)
      names = registry.all_variables.map(&:name)
      expect(names).to include("q")
      expect(names).not_to include("")
    end

    it "collects selected_variables from output nodes" do
      flow = build_flow(
        nodes: [
          node("n1", "input", label: "Start"),
          node("n2", "output", label: "End", data: { "selected_variables" => ["result", "summary"] }),
        ],
        edges: [edge("n1", "n2")],
      )
      registry = described_class.new(flow)
      names = registry.all_variables.map(&:name)
      expect(names).to include("result", "summary")
    end

    it "assigns qualified names using node label" do
      flow = build_flow(
        nodes: [node("n1", "llm", label: "Summarizer")],
      )
      registry = described_class.new(flow)
      qualified = registry.all_variables.filter_map(&:qualified_name)
      expect(qualified).to include("summarizer.response")
    end

    it "assigns suffixed qualified names when duplicate labels repeat" do
      flow = build_flow(
        nodes: [
          node("n1", "json_extract", label: "JSON Extract"),
          node("n2", "json_extract", label: "JSON Extract"),
        ],
      )
      registry = described_class.new(flow)
      qualified = registry.all_variables.filter_map(&:qualified_name)

      expect(qualified).to include("json_extract.parsed", "json_extract_2.parsed")
    end
  end

  describe "#available_at" do
    it "returns only upstream node outputs for a given node" do
      flow = build_flow(
        nodes: [
          node("n1", "input", label: "Start", data: { "fields" => [{ "variable_name" => "query" }] }),
          node("n2", "llm", label: "Writer"),
          node("n3", "output", label: "Output"),
        ],
        edges: [edge("n1", "n2"), edge("n2", "n3")],
      )
      registry = described_class.new(flow)

      at_n3 = registry.available_at("n3")
      qualified = at_n3.filter_map(&:qualified_name)

      # Should include outputs from n1 (query) and n2 (response)
      expect(qualified).to include("start.query", "writer.response")
    end

    it "surfaces both suffixed prefixes at downstream joins when labels repeat" do
      flow = build_flow(
        nodes: [
          node("payload", "text_template", label: "Payload", data: { "template" => '{"first":"a","second":"b"}' }),
          node("j1", "json_extract", label: "JSON Extract", data: { "source" => "{{payload.text}}" }),
          node("j2", "json_extract", label: "JSON Extract", data: { "source" => "{{payload.text}}" }),
          node("join", "set_variable", label: "Join", data: { "assignments" => { "combined" => "1" } }),
        ],
        edges: [edge("payload", "j1"), edge("payload", "j2"), edge("j1", "join"), edge("j2", "join")],
      )
      registry = described_class.new(flow)
      qualified = registry.available_at("join").filter_map(&:qualified_name)

      expect(qualified).to include("json_extract.parsed", "json_extract_2.parsed")
    end

    it "does not include outputs from unconnected branches" do
      flow = build_flow(
        nodes: [
          node("n1", "input", label: "Start", data: { "fields" => [{ "variable_name" => "query" }] }),
          node("n2", "llm", label: "Branch A"),
          node("n3", "llm", label: "Branch B"),
        ],
        edges: [edge("n1", "n2")],
        # n3 has no connection to n2
      )
      registry = described_class.new(flow)

      at_n2 = registry.available_at("n2")
      qualified = at_n2.filter_map(&:qualified_name)

      expect(qualified).to include("start.query")
      expect(qualified).not_to include("branch_b.response")
    end

    it "always includes built-in variables" do
      flow = build_flow(nodes: [node("n1", "llm", label: "Solo")])
      registry = described_class.new(flow)
      names = registry.available_at("n1").map(&:name)
      expect(names).to include("input")
      expect(names).not_to include("_current_node_data", "user_message")
    end

    it "returns only built-in variables for a node_id not present in the flow" do
      flow = build_flow(nodes: [node("n1", "llm", label: "Solo")])
      registry = described_class.new(flow)
      expect(registry.available_at("ghost_node")).to eq(described_class::BUILTIN_VARIABLES)
    end

    it "deduplicates already-visited predecessors in diamond-shaped flows" do
      # A → B, A → C, B → D, C → D  (A is visited twice when computing predecessors of D)
      flow = build_flow(
        nodes: [
          node("a", "input", label: "Start", data: { "fields" => [{ "variable_name" => "query" }] }),
          node("b", "llm", label: "Branch B"),
          node("c", "llm", label: "Branch C"),
          node("d", "output", label: "End"),
        ],
        edges: [edge("a", "b"), edge("a", "c"), edge("b", "d"), edge("c", "d")],
      )
      registry = described_class.new(flow)
      names = registry.available_at("d").map(&:name)
      expect(names).to include("query", "response")
    end

    context "with port-specific variables" do
      it "only includes iterator loop variables for nodes on the loop port" do
        flow = build_flow(
          nodes: [
            node("iter", "iterator", label: "My Iter", data: { "collection" => "[1,2,3]" }),
            node("body", "llm", label: "Body"),
          ],
          edges: [edge("iter", "body", port: "loop")],
        )
        registry = described_class.new(flow)
        at_body = registry.available_at("body")
        qualified = at_body.filter_map(&:qualified_name)

        expect(qualified).to include("my_iter.item", "my_iter.index", "my_iter.total")
        expect(qualified).not_to include("my_iter.results")
      end

      it "only includes iterator done variables for nodes on the done port" do
        flow = build_flow(
          nodes: [
            node("iter", "iterator", label: "My Iter", data: { "collection" => "[1,2,3]" }),
            node("after", "output", label: "After"),
          ],
          edges: [edge("iter", "after", port: "done")],
        )
        registry = described_class.new(flow)
        at_after = registry.available_at("after")
        qualified = at_after.filter_map(&:qualified_name)

        expect(qualified).to include("my_iter.results")
        expect(qualified).not_to include("my_iter.item", "my_iter.index")
      end

      it "propagates port-filtered variables through intermediate nodes" do
        flow = build_flow(
          nodes: [
            node("iter", "iterator", label: "My Iter", data: { "collection" => "[1,2,3]" }),
            node("body", "llm", label: "Body"),
            node("end", "output", label: "End"),
          ],
          edges: [
            edge("iter", "body", port: "loop"),
            edge("body", "end"),
          ],
        )
        registry = described_class.new(flow)
        at_end = registry.available_at("end")
        qualified = at_end.filter_map(&:qualified_name)

        expect(qualified).to include("my_iter.item", "my_iter.index", "my_iter.total")
        expect(qualified).not_to include("my_iter.results")
      end

      it "includes all iterator variables when reachable via an implicit join" do
        flow = build_flow(
          nodes: [
            node("iter", "iterator", label: "My Iter", data: { "collection" => "[1,2,3]" }),
            node("body", "llm", label: "Body"),
            node("after", "llm", label: "After"),
            node("join", "set_variable", label: "Join"),
          ],
          edges: [
            edge("iter", "body", port: "loop"),
            edge("iter", "after", port: "done"),
            edge("body", "join"),
            edge("after", "join"),
          ],
        )
        registry = described_class.new(flow)
        at_join = registry.available_at("join")
        qualified = at_join.filter_map(&:qualified_name)

        expect(qualified).to include("my_iter.item", "my_iter.results")
      end

      it "prevents collision with nested iterators" do
        flow = build_flow(
          nodes: [
            node("outer", "iterator", label: "Outer", data: { "collection" => "[[1],[2]]" }),
            node("inner", "iterator", label: "Inner", data: { "collection" => "outer.item" }),
            node("body", "llm", label: "Body"),
          ],
          edges: [
            edge("outer", "inner", port: "loop"),
            edge("inner", "body", port: "loop"),
          ],
        )
        registry = described_class.new(flow)
        at_body = registry.available_at("body")
        qualified = at_body.filter_map(&:qualified_name)

        expect(qualified).to include("outer.item", "outer.index", "inner.item", "inner.index")
      end

      it "only includes loop iteration variable for nodes on the loop port" do
        flow = build_flow(
          nodes: [
            node("lp", "loop", label: "My Loop", data: { "condition" => "true" }),
            node("body", "llm", label: "Body"),
            node("after", "output", label: "After"),
          ],
          edges: [
            edge("lp", "body", port: "loop"),
            edge("lp", "after", port: "done"),
          ],
        )
        registry = described_class.new(flow)

        at_body = registry.available_at("body")
        body_qualified = at_body.filter_map(&:qualified_name)
        expect(body_qualified).to include("my_loop.iteration")
        expect(body_qualified).not_to include("my_loop.completed")

        at_after = registry.available_at("after")
        after_qualified = at_after.filter_map(&:qualified_name)
        expect(after_qualified).to include("my_loop.completed")
        expect(after_qualified).not_to include("my_loop.iteration")
      end
    end
  end

  describe "#outputs_for_node" do
    it "returns entries for a node with static schema" do
      flow = build_flow(nodes: [node("n1", "llm", label: "My LLM")])
      registry = described_class.new(flow)
      entries = registry.outputs_for_node("n1")

      expect(entries.map(&:name)).to eq(["response"])
      expect(entries.first.qualified_name).to eq("my_llm.response")
      expect(entries.first.node_id).to eq("n1")
    end

    it "returns dynamic entries for set_variable nodes" do
      data = { "assignments" => { "score" => "10", "label" => "good" } }
      flow = build_flow(nodes: [node("n1", "set_variable", label: "Scorer", data:)])
      registry = described_class.new(flow)
      entries = registry.outputs_for_node("n1")

      names = entries.map(&:name)
      expect(names).to contain_exactly("score", "label")
      expect(entries.first.qualified_name).to start_with("scorer.")
    end

    it "skips blank names returned by dynamic output providers" do
      register_dynamic_blank_name_node

      flow = build_flow(nodes: [node("n1", "dynamic_blank_name", label: "Dynamic")])
      registry = described_class.new(flow)
      entries = registry.outputs_for_node("n1")

      expect(entries.map(&:name)).to eq(["value"])
    ensure
      MissionNodePlugin.restore_defaults!
    end

    it "returns empty array for unknown node id" do
      flow = build_flow(nodes: [])
      registry = described_class.new(flow)
      expect(registry.outputs_for_node("nonexistent")).to eq([])
    end

    it "returns empty array for a node with an unregistered type" do
      flow = build_flow(nodes: [node("n1", "totally_unknown_type", label: "Unknown")])
      registry = described_class.new(flow)
      expect(registry.outputs_for_node("n1")).to eq([])
    end

    it "returns entries for agent, output, condition, iterator, loop, mission and switch nodes" do
      ["agent", "output", "condition", "iterator", "loop", "mission", "switch"].each do |node_type|
        flow = build_flow(nodes: [node("n1", node_type, label: "Test")])
        registry = described_class.new(flow)
        expect { registry.outputs_for_node("n1") }.not_to raise_error
      end
    end

    it "returns declared code output variables alongside result" do
      flow = build_flow(
        nodes: [
          node("n1", "code", label: "Transform", data: {
                 "code" => "set('count', 2); 2",
                 "output_variables" => [{ "name" => "count", "description" => "Item count" }],
               },),
        ],
      )
      registry = described_class.new(flow)
      entries = registry.outputs_for_node("n1")

      expect(entries.map(&:name)).to contain_exactly("result", "count")
      expect(entries.map(&:qualified_name)).to include("transform.result", "transform.count")
    end

    it "parses declared code output variables from JSON strings" do
      flow = build_flow(
        nodes: [
          node("n1", "code", label: "Transform", data: {
                 "code" => "set('count', 2); 2",
                 "output_variables" => '[{"name":"count","description":"Item count"}]',
               },),
        ],
      )
      registry = described_class.new(flow)

      expect(registry.outputs_for_node("n1").map(&:name)).to contain_exactly("result", "count")
    end

    it "ignores invalid code output variable JSON" do
      flow = build_flow(
        nodes: [
          node("n1", "code", label: "Transform", data: {
                 "code" => "2",
                 "output_variables" => "not-json",
               },),
        ],
      )
      registry = described_class.new(flow)

      expect(registry.outputs_for_node("n1").map(&:name)).to eq(["result"])
    end

    it "skips blank code output variable names" do
      flow = build_flow(
        nodes: [
          node("n1", "code", label: "Transform", data: {
                 "code" => "2",
                 "output_variables" => [{ "name" => "", "description" => "Ignore me" }],
               },),
        ],
      )
      registry = described_class.new(flow)

      expect(registry.outputs_for_node("n1").map(&:name)).to eq(["result"])
    end

    it "filters by active_ports when provided" do
      flow = build_flow(nodes: [node("n1", "iterator", label: "Iter")])
      registry = described_class.new(flow)

      loop_entries = registry.outputs_for_node("n1", active_ports: Set["loop"])
      expect(loop_entries.map(&:name)).to include("item", "index", "total")
      expect(loop_entries.map(&:name)).not_to include("results")

      done_entries = registry.outputs_for_node("n1", active_ports: Set["done"])
      expect(done_entries.map(&:name)).to include("results")
      expect(done_entries.map(&:name)).not_to include("item")
    end

    it "makes declared code output variables available downstream" do
      flow = build_flow(
        nodes: [
          node("input", "input", label: "Start"),
          node("code", "code", label: "Transform", data: {
                 "code" => "set('count', 2); 2",
                 "output_variables" => [{ "name" => "count", "description" => "Item count" }],
               },),
          node("output", "output", label: "End"),
        ],
        edges: [edge("input", "code"), edge("code", "output")],
      )
      registry = described_class.new(flow)

      qualified = registry.available_at("output").filter_map(&:qualified_name)

      expect(qualified).to include("transform.result", "transform.count")
    end
  end

  describe "#all_variables with a cyclic graph" do
    it "falls back to node_ids order when the flow contains a cycle" do
      flow = build_flow(
        nodes: [
          node("n1", "llm", label: "Step A"),
          node("n2", "llm", label: "Step B"),
        ],
        edges: [edge("n1", "n2"), edge("n2", "n1")],
      )
      registry = described_class.new(flow)
      expect { registry.all_variables }.not_to raise_error
    end
  end

  describe "global variables" do
    it "includes global variables in all_variables" do
      flow = build_flow(
        nodes: [node("n1", "llm", label: "Step A")],
        edges: [],
      )
      flow["global_variables"] = [
        { "key" => "api_key", "value" => "secret", "type" => "string" },
        { "key" => "threshold", "value" => "0.8", "type" => "number" },
        { "key" => "enabled", "value" => "true", "type" => "boolean" },
      ]
      registry = described_class.new(flow)
      all = registry.all_variables
      global_names = all.select { |e| e.node_id.nil? }.map(&:qualified_name)
      expect(global_names).to include("api_key", "threshold", "enabled")
    end

    it "maps boolean type for global variables" do
      flow = build_flow(nodes: [], edges: [])
      flow["global_variables"] = [
        { "key" => "flag", "value" => "true", "type" => "boolean" },
      ]
      registry = described_class.new(flow)
      entry = registry.all_variables.find { |e| e.name == "flag" }
      expect(entry.type).to eq(:boolean)
    end

    it "makes global variables available at every node" do
      flow = build_flow(
        nodes: [node("n1", "llm", label: "Step A")],
        edges: [],
      )
      flow["global_variables"] = [
        { "key" => "api_key", "value" => "secret", "type" => "string" },
      ]
      registry = described_class.new(flow)
      available = registry.available_at("n1")
      qualified_names = available.map(&:qualified_name)
      expect(qualified_names).to include("api_key")
    end

    it "skips global variables with blank keys" do
      flow = build_flow(
        nodes: [node("n1", "llm", label: "Step A")],
        edges: [],
      )
      flow["global_variables"] = [
        { "key" => "", "value" => "skip_me", "type" => "string" },
        { "key" => nil, "value" => "skip_too", "type" => "string" },
        { "key" => "valid", "value" => "keep", "type" => "string" },
      ]
      registry = described_class.new(flow)
      names = registry.all_variables.map(&:name)
      expect(names).to include("valid")
      expect(names).not_to include("")
      expect(names).not_to include(nil)
    end
  end
end
