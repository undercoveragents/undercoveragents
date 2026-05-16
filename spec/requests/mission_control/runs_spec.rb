# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MissionControl::Runs" do
  let(:mission) { create(:mission, name: "Test Mission") }

  describe "GET /admin/mission_control/runs" do
    it "returns a successful response when no runs exist" do
      get admin_mission_control_runs_path
      expect(response).to have_http_status(:ok)
    end

    it "displays the Mission Control title" do
      get admin_mission_control_runs_path
      expect(response.body).to include("Mission Control")
    end

    it "shows the empty state when no runs exist" do
      get admin_mission_control_runs_path
      expect(response.body).to include("No runs found")
    end

    context "when runs exist" do
      let!(:run) do
        create(:mission_run, mission:, status: "completed",
                             started_at: 5.minutes.ago, completed_at: 1.minute.ago,)
      end

      it "shows run list" do
        get admin_mission_control_runs_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Test Mission")
      end

      it "shows run ID" do
        get admin_mission_control_runs_path
        expect(response.body).to include(run.id.to_s)
      end

      it "shows run status" do
        get admin_mission_control_runs_path
        expect(response.body).to include("completed")
      end
    end

    context "with filters" do
      let!(:completed_run) do
        create(:mission_run, mission:, status: "completed",
                             started_at: 10.minutes.ago, completed_at: 5.minutes.ago,)
      end
      let!(:failed_run) do
        create(:mission_run, mission:, status: "failed",
                             started_at: 3.minutes.ago, completed_at: 1.minute.ago,
                             error: "Something went wrong",)
      end

      it "filters by status" do
        get admin_mission_control_runs_path, params: { q: { status_eq: "completed" } }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(completed_run.id.to_s)
      end

      it "filters by mission_id" do
        get admin_mission_control_runs_path, params: { q: { mission_id_eq: mission.id } }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Test Mission")
      end

      it "filters by id" do
        get admin_mission_control_runs_path, params: { q: { id_eq: failed_run.id } }
        expect(response).to have_http_status(:ok)
      end

      it "filters by operation" do
        other_op = create(:operation, name: "Ops Gamma")
        other_mission = create(:mission, name: "Gamma Mission", operation: other_op)
        create(:mission_run, mission: other_mission, status: "completed",
                             started_at: 2.minutes.ago, completed_at: 1.minute.ago,)
        get admin_mission_control_runs_path, params: { operation: other_op.slug }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Gamma Mission")
      end
    end
  end

  describe "GET /admin/mission_control/runs/:id" do
    let(:flow_snapshot) do
      {
        "nodes" => [
          { "id" => "n1", "type" => "input", "data" => { "label" => "Start" } },
          { "id" => "n2", "type" => "llm", "data" => { "label" => "Generate Text" } },
          { "id" => "n3", "type" => "output", "data" => { "label" => "End" } },
        ],
        "edges" => [
          { "id" => "e1", "source" => "n1", "target" => "n2" },
          { "id" => "e2", "source" => "n2", "target" => "n3" },
        ],
      }
    end

    let(:execution_state) do
      {
        "execution_log" => [
          {
            "node_id" => "n1",
            "node_type" => "input",
            "status" => "success",
            "output" => "Started",
            "next_port" => "default",
            "started_at" => 5.minutes.ago.iso8601(3),
            "finished_at" => 5.minutes.ago.iso8601(3),
            "error" => nil,
          },
          {
            "node_id" => "n2",
            "node_type" => "llm",
            "status" => "success",
            "input" => { "prompt" => "Write a summary" },
            "output" => "Generated text response",
            "next_port" => "default",
            "started_at" => 4.minutes.ago.iso8601(3),
            "finished_at" => 3.minutes.ago.iso8601(3),
            "error" => nil,
          },
          {
            "node_id" => "n3",
            "node_type" => "output",
            "status" => "success",
            "output" => "Finished",
            "next_port" => nil,
            "started_at" => 3.minutes.ago.iso8601(3),
            "finished_at" => 3.minutes.ago.iso8601(3),
            "error" => nil,
          },
        ],
        "edge_states" => { "e1" => "completed", "e2" => "completed" },
        "variables" => { "user_input" => "Hello world" },
      }
    end

    let(:run) do
      create(:mission_run, mission:, status: "completed",
                           started_at: 5.minutes.ago, completed_at: 1.minute.ago,
                           flow_snapshot:, execution_state:,
                           variables: { "result" => "Generated text" },
                           trigger_data: { "message" => "Hello" },)
    end

    let(:incomplete_execution_log_entry) do
      {
        "node_id" => "n1",
        "node_type" => "llm",
        "status" => "success",
        "output" => "done",
        "next_port" => nil,
        "started_at" => 2.minutes.ago.iso8601(3),
        "finished_at" => nil,
        "error" => nil,
      }
    end
    let(:incomplete_run) do
      create(
        :mission_run,
        mission:,
        status: "completed",
        started_at: 3.minutes.ago,
        completed_at: 1.minute.ago,
        flow_snapshot: { "nodes" => [{ "id" => "n1", "type" => "llm", "data" => { "label" => "Step" } }] },
        execution_state: { "execution_log" => [incomplete_execution_log_entry] },
      )
    end

    it "returns a successful response" do
      get admin_mission_control_run_path(run)
      expect(response).to have_http_status(:ok)
    end

    it "displays the mission name" do
      get admin_mission_control_run_path(run)
      expect(response.body).to include("Test Mission")
    end

    it "displays the run ID" do
      get admin_mission_control_run_path(run)
      expect(response.body).to include(run.id.to_s)
    end

    it "displays the run status" do
      get admin_mission_control_run_path(run)
      expect(response.body).to include("completed")
    end

    it "shows execution stats in the top summary cards" do
      get admin_mission_control_run_path(run)

      expect(response.body).to include("Execution Stats")
      expect(response.body).to include("Total Steps")
      expect(response.body).to include("Total Exec Time")
    end

    it "shows the execution timeline" do
      get timeline_admin_mission_control_run_path(run)
      expect(response.body).to include("Execution Timeline")
      expect(response.body).to include("3 steps")
    end

    it "shows node labels from flow_snapshot" do
      get timeline_admin_mission_control_run_path(run)
      expect(response.body).to include("Start")
      expect(response.body).to include("Generate Text")
      expect(response.body).to include("End")
    end

    it "shows node types" do
      get timeline_admin_mission_control_run_path(run)
      expect(response.body).to include("input")
      expect(response.body).to include("llm")
      expect(response.body).to include("output")
    end

    it "shows node inputs in the execution timeline" do
      get timeline_admin_mission_control_run_path(run)

      expect(response.body).to include("Input")
      expect(response.body).to include("Write a summary")
    end

    it "shows variables" do
      get admin_mission_control_run_path(run)
      expect(response.body).to include("result")
      expect(response.body).to include("Generated text")
    end

    it "shows trigger data" do
      get admin_mission_control_run_path(run)
      expect(response.body).to include("Trigger Data")
      expect(response.body).to include("Hello")
    end

    it "does not show raw execution state section" do
      get timeline_admin_mission_control_run_path(run)
      expect(response.body).not_to include("Raw Execution State")
    end

    it "renders an empty flow map when the run has no flow snapshot" do
      run_without_snapshot = create(
        :mission_run,
        mission:,
        status: "completed",
        started_at: 2.minutes.ago,
        completed_at: 1.minute.ago,
        flow_snapshot: {},
        execution_state: {},
      )

      get timeline_admin_mission_control_run_path(run_without_snapshot)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Execution Timeline (0 steps)")
    end

    it "skips incomplete execution durations when building execution stats" do
      get admin_mission_control_run_path(incomplete_run)

      expect(response.body).to include("Execution Stats")
      expect(response.body).to include("Total Exec Time")
      expect(response.body).to include("—")
    end

    it "does not show the list link in the header" do
      get admin_mission_control_run_path(run)
      expect(response.body).not_to include("All Runs")
    end

    it "shows open in designer link" do
      get admin_mission_control_run_path(run)
      expect(response.body).to include("Open in designer")
    end

    it "does not render agent chats before the run has started" do
      pending_run = create(
        :mission_run,
        mission:,
        status: "pending",
        started_at: nil,
        completed_at: nil,
        flow_snapshot: { "nodes" => [], "edges" => [] },
        execution_state: {},
      )
      create(:chat, title: "Mission run chat", mission:, execution_context: :mission, created_at: 1.minute.ago)

      get admin_mission_control_run_path(pending_run)

      expect(response.body).not_to include("Agent &amp; LLM Chats")
      expect(response.body).not_to include("Mission run chat")
    end

    context "with a failed run" do
      let(:failed_run) do
        create(:mission_run, mission:, status: "failed",
                             started_at: 5.minutes.ago, completed_at: 1.minute.ago,
                             flow_snapshot:, error: "Node execution timed out",
                             execution_state: {
                               "execution_log" => [
                                 {
                                   "node_id" => "n2",
                                   "node_type" => "llm",
                                   "status" => "failure",
                                   "output" => "Timeout reached",
                                   "next_port" => nil,
                                   "started_at" => 4.minutes.ago.iso8601(3),
                                   "finished_at" => 3.minutes.ago.iso8601(3),
                                   "error" => "Node execution timed out",
                                 },
                               ],
                             },)
      end

      it "shows error details" do
        get admin_mission_control_run_path(failed_run)
        expect(response.body).to include("Node execution timed out")
      end

      it "shows failed status" do
        get admin_mission_control_run_path(failed_run)
        expect(response.body).to include("failed")
      end
    end

    context "with agent chats" do
      before do
        create(:chat, title: "Mission — Generate Text",
                      mission: run.mission,
                      execution_context: :mission,
                      created_at: run.started_at + 1.minute,)
      end

      it "shows agent chats panel" do
        get admin_mission_control_run_path(run)
        expect(response.body).to include("Agent &amp; LLM Chats")
          .or include("Agent & LLM Chats")
        expect(response.body).to include("Mission — Generate Text")
          .or include("Mission &#8212; Generate Text")
      end
    end
  end
end
