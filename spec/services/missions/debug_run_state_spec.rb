# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::DebugRunState do
  let(:mission) do
    create(:mission, flow_data: {
             "nodes" => [
               { "id" => "n1", "type" => "set_variable", "data" => { "label" => "Set API Key" } },
               { "id" => "n2", "type" => "llm", "data" => { "label" => "Draft Reply" } },
               { "id" => "iter1", "type" => "iterator", "data" => { "label" => "Loop Items" } },
             ],
             "edges" => [],
             "global_variables" => [
               { "key" => "api_key" },
               { "key" => "" },
             ],
           },)
  end

  describe "execution log enrichment" do
    let(:run) do
      build(:mission_run,
            mission:,
            status: "running",
            flow_snapshot: { "nodes" => [], "edges" => [] },
            execution_state: {
              "execution_log" => [
                {
                  "node_id" => "n1",
                  "node_type" => "set_variable",
                  "status" => "success",
                  "next_port" => "default",
                  "started_at" => "not-a-time",
                  "finished_at" => "still-not-a-time",
                },
              ],
            },)
    end

    it "falls back to the current mission flow for node labels and ignores invalid timestamps" do
      state = described_class.new(mission:, run:)

      expect(state.execution_log).to contain_exactly(
        hash_including(
          "node_id" => "n1",
          "node_label" => "Set API Key",
        ),
      )
      expect(state.execution_log.first["duration_ms"]).to be_nil
    end
  end

  describe "projection helpers" do
    subject(:state) { described_class.new(mission:, run:) }

    let(:started_at) { Time.zone.parse("2024-04-01 10:00:00") }
    let(:completed_at) { Time.zone.parse("2024-04-01 10:00:01.250") }
    let(:run) do
      build(:mission_run,
            mission:,
            status: "running",
            started_at:,
            completed_at:,
            flow_snapshot: { "nodes" => [], "edges" => [], "global_variables" => [] },
            variables: {
              "api_key" => "secret",
              "_internal" => "hidden",
            },
            execution_state: {
              "execution_log" => [
                {
                  "node_id" => "n1",
                  "node_type" => "set_variable",
                  "status" => "success",
                  "next_port" => "default",
                  "duration_ms" => 11.5,
                },
                {
                  "node_id" => "n2",
                  "node_type" => "llm",
                  "status" => "running",
                  "next_port" => "default",
                },
                {
                  "node_id" => "iter1",
                  "node_type" => "iterator",
                  "status" => "success",
                  "next_port" => "done",
                  "output" => ["one", "two"],
                },
              ],
              "node_states" => {
                "persisted" => {
                  "status" => "running",
                  "node_type" => "llm",
                  "next_port" => "default",
                  "duration_ms" => 3.5,
                  "completed_count" => 1,
                },
              },
              "edge_states" => {
                "edge-1" => "disabled",
              },
            },)
    end

    it "builds canvas node and edge state for active runs" do
      expect(state.canvas_node_states).to include(
        "persisted" => hash_including(status: "running", node_type: "llm", completed_count: 0),
        "n1" => hash_including(status: "success", node_type: "set_variable", completed_count: 1),
        "n2" => hash_including(status: "running", node_type: "llm", completed_count: 0),
        "iter1" => hash_including(status: "success", node_type: "iterator", completed_count: 2),
      )
      expect(state.canvas_edge_states).to eq({ "edge-1" => { status: "disabled" } })
    end

    it "builds live node and edge event payloads" do
      expect(state.node_event_payloads).to include(
        hash_including("node-id" => "n1", state: "success", "completed-count" => 1),
        hash_including("node-id" => "n2", state: "running"),
        hash_including("node-id" => "iter1", state: "success", "completed-count" => 2),
      )
      expect(state.node_event_payloads.find { |payload| payload["node-id"] == "n2" })
        .not_to have_key("completed-count")
      expect(state.persisted_node_state_payloads).to contain_exactly(
        hash_including(
          "node-id" => "persisted",
          "node-type" => "llm",
          state: "running",
          "completed-count" => 1,
        ),
      )
      expect(state.edge_event_payloads).to contain_exactly({ "edge-id" => "edge-1", "edge-state" => "disabled" })
    end

    it "omits completed counts when runtime completion data is unavailable" do
      state_without_counts = Class.new(described_class) do
        def node_completion_counts
          {}
        end
      end.new(mission:, run:)

      expect(state_without_counts.node_event_payloads).to all(satisfy { |payload| !payload.key?("completed-count") })
    end

    it "filters persisted variables using the visible global keys" do
      expect(state.variables).to eq({ "api_key" => "secret" })
      expect(state.filtered_variables(fallback: :none)).to eq({ "api_key" => "secret" })
      expect(state.filtered_variables(fallback: :none, keys: [])).to eq({})
      expect(state.global_variable_keys).to eq(["api_key"])
    end

    it "reports the run duration in milliseconds" do
      expect(state.duration_ms).to eq(1250.0)
    end
  end

  describe "inactive projections" do
    let(:run) do
      build(:mission_run,
            mission:,
            status: "completed",
            execution_state: {
              "node_states" => { "n1" => { "status" => "success" } },
              "edge_states" => { "edge-1" => "success" },
            },)
    end

    it "returns empty canvas state when the run is no longer active" do
      state = described_class.new(mission:, run:)

      expect(state.canvas_node_states).to eq({})
      expect(state.canvas_edge_states).to eq({})
    end
  end
end
