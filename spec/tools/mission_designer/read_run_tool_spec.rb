# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::ReadRunTool do
  let(:mission) { create(:mission) }
  let(:user) { create(:user, :admin, tenant: mission.operation.tenant) }
  let(:runtime_context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission:,
      ui_context: nil,
      user:,
      tenant: mission.operation.tenant,
      operation: mission.operation,
    )
  end
  let(:tool) { described_class.new(mission, runtime_context:) }

  describe "#name" do
    it "returns read_mission_run" do
      expect(tool.name).to eq("read_mission_run")
    end
  end

  describe "#execute" do
    let!(:older_run) do
      create(
        :mission_run,
        mission:,
        status: "failed",
        trigger_data: { "name" => "Old" },
        variables: { "name" => "Old" },
        execution_state: {
          "execution_log" => [
            {
              "node_id" => "node-1",
              "node_type" => "input",
              "status" => "failure",
              "input" => { "name" => "Old" },
              "output" => nil,
              "started_at" => 2.minutes.ago.iso8601(3),
              "finished_at" => 2.minutes.ago.iso8601(3),
              "error" => "boom",
            },
          ],
        },
        error: "boom",
        created_at: 2.minutes.ago,
        started_at: 2.minutes.ago,
        completed_at: 2.minutes.ago,
      )
    end
    let!(:latest_run) do
      create(
        :mission_run,
        mission:,
        status: "completed",
        trigger_data: { "name" => "Ada" },
        variables: { "name" => "Ada", "result" => "ok", "_output_meta" => { "status" => 200 } },
        execution_state: {
          "node_outputs" => { "node-1" => { "name" => "Ada" } },
          "execution_log" => [
            {
              "node_id" => "node-1",
              "node_type" => "input",
              "node_label" => "Input",
              "status" => "success",
              "input" => { "name" => "Ada" },
              "output" => { "name" => "Ada" },
              "next_port" => "default",
              "started_at" => 1.minute.ago.iso8601(3),
              "finished_at" => 1.minute.ago.iso8601(3),
            },
            {
              "node_id" => "node-2",
              "node_type" => "output",
              "node_label" => "Output",
              "status" => "success",
              "input" => { "selected_variables" => ["name", "result"] },
              "output" => { "name" => "Ada", "result" => "ok" },
              "started_at" => 1.minute.ago.iso8601(3),
              "finished_at" => 1.minute.ago.iso8601(3),
            },
          ],
        },
        created_at: 1.minute.ago,
        started_at: 1.minute.ago,
        completed_at: 1.minute.ago,
      )
    end

    it "returns the latest run by default" do
      result = tool.execute

      expect(result).to include(
        "run_id: `#{latest_run.id}`",
        "status: completed",
        "Trigger Data",
        "Ada",
      )
    end

    it "accepts the explicit latest selector" do
      result = tool.execute(selector: "latest")

      expect(result).to include("run_id: `#{latest_run.id}`", "status: completed")
    end

    it "requires a mission context when none is available" do
      result = described_class.new(nil, runtime_context: nil).execute

      expect(result).to eq("Error reading mission runs: #{described_class::MISSING_MISSION_MESSAGE}")
    end

    it "reads a specific run by id" do
      result = tool.execute(run_id: older_run.id)

      expect(result).to include(
        "run_id: `#{older_run.id}`",
        "status: failed",
        "## Error",
        "boom",
      )
    end

    it "lists recent runs" do
      result = tool.execute(selector: "recent", limit: 2)

      expect(result).to include(
        "## Recent Mission Runs (2)",
        "run_id=`#{latest_run.id}` status=completed",
        "run_id=`#{older_run.id}` status=failed",
      )
    end

    it "returns full execution details when requested" do
      result = tool.execute(run_id: latest_run.id, detail: "full")

      expect(result).to include(
        "## Node Outputs",
        "### Step 1",
        "### Step 2",
        "- input:",
        "- output:",
      )
    end

    it "returns a helpful message when no runs exist" do
      mission.mission_runs.delete_all

      expect(tool.execute).to eq("No mission runs found for '#{mission.name}'.")
    end

    it "returns a helpful message when a run id does not belong to the mission" do
      other_run = create(:mission_run)

      result = tool.execute(run_id: other_run.id)

      expect(result).to eq("No mission run with ID '#{other_run.id}' was found for '#{mission.name}'.")
    end

    it "returns an authorization error when the reader is not allowed" do
      regular_user = create(:user, tenant: mission.operation.tenant)
      unauthorized_context = BuiltinTools::RuntimeContext::Context.new(
        agent: nil,
        chat: nil,
        mission:,
        ui_context: nil,
        user: regular_user,
        tenant: mission.operation.tenant,
        operation: mission.operation,
      )

      result = described_class.new(mission, runtime_context: unauthorized_context).execute

      expect(result).to eq("Error: You do not have permission to do that.")
    end

    it "reads runs without authorization context when a mission is provided directly" do
      result = described_class.new(mission, runtime_context: nil).execute(selector: "latest")

      expect(result).to include("run_id: `#{latest_run.id}`", "status: completed")
    end

    it "rejects unknown selectors" do
      result = tool.execute(selector: "bogus")

      expect(result).to include("selector must be one of: latest, recent")
    end

    it "returns nil for an unexpected normalized selector branch" do
      allow(tool).to receive(:normalize_selector).and_return("unexpected")

      result = tool.send(
        :read_selected_runs,
        mission,
        selector: nil,
        limit: nil,
        detail: nil,
      )

      expect(result).to be_nil
    end
  end
end
