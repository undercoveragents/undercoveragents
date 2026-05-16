# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::LoopBodyBoundaryValidator do
  def loop_flow(body_edges: [], done_edges: [])
    {
      "nodes" => [
        { "id" => "input", "type" => "input", "data" => { "label" => "Input" } },
        { "id" => "loop", "type" => "loop", "data" => { "label" => "Repeat Delay", "max_iterations" => 5 } },
        { "id" => "body", "type" => "delay", "data" => { "label" => "Wait", "duration" => 1, "unit" => "seconds" } },
        { "id" => "body_2", "type" => "delay",
          "data" => { "label" => "Wait Again", "duration" => 1, "unit" => "seconds" }, },
        { "id" => "join", "type" => "set_variable",
          "data" => { "label" => "Join", "assignments" => { "value" => "1" } }, },
        { "id" => "output", "type" => "output", "data" => { "label" => "Output" } },
      ],
      "edges" => [
        { "id" => "e1", "source" => "input", "target" => "loop", "sourceHandle" => "default" },
        { "id" => "e2", "source" => "loop", "target" => "body", "sourceHandle" => "loop" },
        { "id" => "e3", "source" => "body", "target" => "body_2", "sourceHandle" => "default" },
        { "id" => "e4", "source" => "loop", "target" => "output", "sourceHandle" => "done" },
        *body_edges,
        *done_edges,
      ],
    }
  end

  describe ".errors_for" do
    it "deduplicates repeated loop-body reentry errors" do
      flow = loop_flow(body_edges: [
                         { "id" => "e5", "source" => "body", "target" => "loop", "sourceHandle" => "default" },
                         { "id" => "e6", "source" => "body_2", "target" => "loop", "sourceHandle" => "default" },
                       ])

      errors = described_class.errors_for(flow)

      expect(errors.count { |error| error.node_id == "loop" }).to eq(1)
    end

    it "skips body nodes that no longer resolve to an incoming edge" do
      validator = described_class.new(loop_flow)
      graph = validator.instance_variable_get(:@graph)

      allow(validator).to receive(:control_node_ids).and_return(["loop"])
      allow(validator).to receive(:loop_body_node_ids).with("loop").and_return(Set["ghost_body"])
      allow(graph).to receive(:incoming_edges).and_call_original
      allow(graph).to receive(:incoming_edges).with("ghost_body").and_return([])

      expect(validator.errors).to eq([])
    end
  end

  describe ".error_for_candidate_edge" do
    it "returns nil when the validator has no candidate edge" do
      expect(described_class.new(loop_flow).candidate_error).to be_nil
    end

    it "allows normal entry edges into a loop node from outside the body" do
      message = described_class.error_for_candidate_edge(
        flow_data: loop_flow,
        source_node_id: "input",
        target_node_id: "loop",
      )

      expect(message).to be_nil
    end

    it "rejects reconnecting a loop body back into its loop node" do
      message = described_class.error_for_candidate_edge(
        flow_data: loop_flow,
        source_node_id: "body_2",
        target_node_id: "loop",
      )

      expect(message).to match(/cannot receive an incoming edge from its own body/i)
    end

    it "rejects body-fed nodes that also receive done-port input" do
      flow = loop_flow(done_edges: [
                         { "id" => "e5", "source" => "loop", "target" => "join", "sourceHandle" => "done" },
                       ])

      message = described_class.error_for_candidate_edge(
        flow_data: flow,
        source_node_id: "body_2",
        target_node_id: "join",
      )

      expect(message).to match(%r{mixes inputs from inside and outside loop/iterator body}i)
    end

    it "rejects outside inputs that target an existing body-fed node" do
      flow = loop_flow(body_edges: [
                         { "id" => "e5", "source" => "body_2", "target" => "join", "sourceHandle" => "default" },
                       ])

      message = described_class.error_for_candidate_edge(
        flow_data: flow,
        source_node_id: "loop",
        target_node_id: "join",
        source_port: "done",
      )

      expect(message).to match(%r{mixes inputs from inside and outside loop/iterator body}i)
    end

    it "allows extending the loop body with more body-only nodes" do
      message = described_class.error_for_candidate_edge(
        flow_data: loop_flow,
        source_node_id: "body_2",
        target_node_id: "join",
      )

      expect(message).to be_nil
    end

    it "treats blank-source edges as outside the loop body" do
      validator = described_class.new(loop_flow)

      result = validator.send(
        :inside_body_edge?,
        "loop",
        Set["body", "body_2"],
        { "source" => "", "sourceHandle" => "default" },
      )

      expect(result).to be(false)
    end
  end
end
