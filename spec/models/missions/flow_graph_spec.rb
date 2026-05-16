# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::FlowGraph do
  # ── helpers ──────────────────────────────────────────────────────────

  def node(id, type: "set_variable")
    { "id" => id, "type" => type, "data" => {} }
  end

  def edge(source, target, handle: "default")
    { "source" => source, "target" => target, "sourceHandle" => handle }
  end

  def graph(*nodes, edges: [])
    described_class.new({ "nodes" => nodes, "edges" => edges })
  end

  # ── accessors ─────────────────────────────────────────────────────────

  describe "#node / #node_type / #node_data / #node_ids" do
    let(:g) { graph(node("n1", type: "llm")) }

    it "looks up a node by id" do
      expect(g.node("n1")).to include("id" => "n1", "type" => "llm")
    end

    it "looks up the type for a given id" do
      expect(g.node_type("n1")).to eq("llm")
    end

    it "returns an empty hash as node_data when none is set" do
      expect(g.node_data("n1")).to eq({})
    end

    it "returns nil for an unknown node" do
      expect(g.node("unknown")).to be_nil
    end

    it "lists all node ids" do
      expect(g.node_ids).to contain_exactly("n1")
    end
  end

  # ── edge traversal ────────────────────────────────────────────────────

  describe "#successors / #predecessors / #outgoing_edges" do
    let(:g) { graph(node("a"), node("b"), node("c"), edges: [edge("a", "b"), edge("a", "c")]) }

    it "returns successors of a node" do
      expect(g.successors("a")).to contain_exactly("b", "c")
    end

    it "filters successors by port" do
      expect(g.successors("a", port: "default")).to contain_exactly("b", "c")
      expect(g.successors("a", port: "other")).to be_empty
    end

    it "returns predecessors of a node" do
      expect(g.predecessors("b")).to contain_exactly("a")
    end

    it "deduplicates predecessors reached by multiple ports" do
      g = graph(
        node("cond", type: "condition"),
        node("out", type: "output"),
        edges: [edge("cond", "out", handle: "true"), edge("cond", "out", handle: "false")],
      )

      expect(g.predecessors("out")).to contain_exactly("cond")
    end

    it "deduplicates successors when multiple ports target the same node" do
      g = graph(
        node("cond", type: "condition"),
        node("out", type: "output"),
        edges: [edge("cond", "out", handle: "true"), edge("cond", "out", handle: "false")],
      )

      expect(g.successors("cond")).to contain_exactly("out")
    end

    it "returns outgoing edges optionally filtered by port" do
      all_edges = g.outgoing_edges("a")
      expect(all_edges.size).to eq(2)
      filtered = g.outgoing_edges("a", port: "default")
      expect(filtered.size).to eq(2)
    end
  end

  # ── graph queries ─────────────────────────────────────────────────────

  describe "#root_nodes / #leaf_nodes" do
    let(:g) { graph(node("a"), node("b"), node("c"), edges: [edge("a", "b"), edge("b", "c")]) }

    it "identifies root nodes (no incoming edges)" do
      expect(g.root_nodes.pluck("id")).to contain_exactly("a")
    end

    it "identifies leaf nodes (no outgoing edges)" do
      expect(g.leaf_nodes.pluck("id")).to contain_exactly("c")
    end
  end

  describe "#trigger_nodes / #output_nodes" do
    context "when node types are registered in MissionNodePlugin" do
      it "returns trigger nodes for type 'input'" do
        g = graph(node("t1", type: "input"), node("o1", type: "output"))
        expect(g.trigger_nodes.pluck("id")).to include("t1")
        expect(g.output_nodes.pluck("id")).to include("o1")
      end
    end

    context "when node types are NOT registered (infer_category fallback)" do
      before { MissionNodePlugin.reset! }

      after { MissionNodePlugin.restore_defaults! }

      it "infers 'trigger' for type containing the word 'trigger'" do
        g = graph(node("t1", type: "custom_trigger_node"))
        expect(g.trigger_nodes.pluck("id")).to include("t1")
      end

      it "infers 'input_output' for type == 'input'" do
        g = graph(node("t1", type: "input"))
        expect(g.trigger_nodes.pluck("id")).to include("t1")
      end

      it "infers 'output' category for type containing the word 'output'" do
        g = graph(node("o1", type: "chat_output_node"))
        expect(g.send(:category_for, g.nodes.values.first)).to eq("output")
      end

      it "infers 'input_output' for type == 'output'" do
        g = graph(node("o1", type: "output"))
        expect(g.output_nodes.pluck("id")).to include("o1")
      end

      it "infers 'control' for condition/switch/iterator/loop types" do
        g = graph(node("c1", type: "condition"))
        expect(g.send(:category_for, g.nodes.values.first)).to eq("control")
      end

      it "infers 'node' for unknown types" do
        g = graph(node("n1", type: "totally_unknown_type"))
        expect(g.trigger_nodes).to be_empty
        expect(g.output_nodes).to be_empty
      end
    end
  end

  # ── topological sort ──────────────────────────────────────────────────

  describe "#topological_sort" do
    it "returns nodes in dependency order for a linear graph" do
      g = graph(node("a"), node("b"), node("c"), edges: [edge("a", "b"), edge("b", "c")])
      sorted = g.topological_sort
      expect(sorted.index("a")).to be < sorted.index("b")
      expect(sorted.index("b")).to be < sorted.index("c")
    end

    it "treats duplicate predecessor edges as one dependency" do
      g = graph(
        node("cond", type: "condition"),
        node("after", type: "output"),
        node("done", type: "set_variable"),
        edges: [edge("cond", "after", handle: "true"), edge("cond", "after", handle: "false"), edge("after", "done")],
      )

      expect(g.topological_sort).to eq(["cond", "after", "done"])
    end

    it "raises CyclicGraphError when the graph contains a cycle" do
      g = graph(
        node("a"), node("b"),
        edges: [edge("a", "b"), edge("b", "a")],
      )
      expect { g.topological_sort }.to raise_error(Missions::CyclicGraphError, /cycle/)
    end
  end

  # ── validate! ─────────────────────────────────────────────────────────

  describe "#validate!" do
    it "raises InvalidFlowError when there are no nodes" do
      g = graph
      expect { g.validate! }.to raise_error(Missions::InvalidFlowError, /No nodes/)
    end

    it "raises InvalidFlowError when an edge references a missing target node" do
      g = described_class.new({
                                "nodes" => [node("a", type: "input")],
                                "edges" => [{ "source" => "a", "target" => "nonexistent" }],
                              })
      expect { g.validate! }.to raise_error(Missions::InvalidFlowError, /missing target/)
    end

    it "raises InvalidFlowError when an edge references a missing source node" do
      g = described_class.new({
                                "nodes" => [node("a", type: "input")],
                                "edges" => [{ "source" => "nonexistent", "target" => "a" }],
                              })
      expect { g.validate! }.to raise_error(Missions::InvalidFlowError, /missing source/)
    end

    it "returns true for a valid flow" do
      g = graph(node("a", type: "input"))
      expect(g.validate!).to be(true)
    end
  end
end
