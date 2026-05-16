# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::RunFormatter do
  subject(:formatter) { described_class.new(mission:) }

  let(:mission) do
    create(
      :mission,
      flow_data: {
        "nodes" => [
          { "id" => "node-1", "data" => { "label" => "Input" } },
          { "id" => "node-2", "data" => { "label" => "Transform" } },
          { "id" => "node-3", "data" => { "label" => "Output" } },
        ],
        "edges" => [],
      },
    )
  end

  describe "#format_run" do
    it "formats summary output with truncated previews and omitted steps" do
      result = formatter.format_run(build_summary_run)

      expect_summary_output(result)
    end

    it "formats full details with node outputs, errors, and placeholder values" do
      result = formatter.format_run(build_full_detail_run, detail: "full")

      expect_full_detail_output(result)
    end

    it "reports when no node executions were recorded" do
      run = create(:mission_run, mission:, status: "completed", execution_state: {}, trigger_data: {}, variables: {})

      result = formatter.format_run(run, detail: "full")

      expect(result).to include("## Execution Log (0)", "No node executions recorded.")
    end

    it "ignores output meta when variables are not a hash" do
      run = build_stubbed(
        :mission_run,
        mission:,
        status: "completed",
        trigger_data: {},
        execution_state: {},
        variables: nil,
      )

      result = formatter.format_run(run)

      expect(result).not_to include("## Output Meta")
    end
  end

  describe "#format_recent_runs" do
    it "clamps the requested limit and includes optional metadata" do
      runs = build_recent_runs

      expect(formatter.format_recent_runs(runs, limit: 0)).to include("## Recent Mission Runs (1)")

      result = formatter.format_recent_runs(runs, limit: 99)

      expect(result).to include("## Recent Mission Runs (10)", "current_node=node-2", "error=", "(truncated)")
    end

    it "returns a helpful message when there are no runs" do
      expect(formatter.format_recent_runs([], limit: 3)).to eq("No mission runs found for '#{mission.name}'.")
    end

    it "treats missing execution logs as zero steps" do
      run = build_stubbed(
        :mission_run,
        mission:,
        status: "completed",
        execution_state: nil,
        created_at: Time.current,
        started_at: 5.seconds.ago,
        completed_at: Time.current,
      )

      result = formatter.format_recent_runs([run], limit: 1)

      expect(result).to include("steps=0")
    end
  end

  def build_summary_run
    long_value = "A" * 400

    create(
      :mission_run,
      mission:,
      status: "running",
      current_node_id: "node-2",
      trigger_data: { "payload" => long_value },
      variables: {
        "visible" => long_value,
        "_output_meta" => { "status" => 202, "response" => long_value },
      },
      execution_state: { "execution_log" => summary_execution_log(long_value) },
      started_at: 2.minutes.ago,
      completed_at: nil,
    )
  end

  def build_full_detail_run
    long_error = "E" * 5_000

    create(
      :mission_run,
      mission:,
      status: "failed",
      trigger_data: {},
      variables: {},
      execution_state: full_detail_execution_state(long_error),
      error: long_error,
      started_at: nil,
      completed_at: nil,
    )
  end

  def build_recent_runs
    Array.new(12) do |index|
      build_stubbed(
        :mission_run,
        mission:,
        status: index.zero? ? "failed" : "completed",
        current_node_id: index.zero? ? "node-2" : nil,
        error: index.zero? ? ("B" * 400) : nil,
        execution_state: { "execution_log" => Array.new(index + 1) { {} } },
        created_at: index.minutes.ago,
        started_at: 5.minutes.ago,
        completed_at: 4.minutes.ago,
      )
    end
  end

  def summary_execution_log(long_value)
    [
      success_execution_entry("node-1", "input", 1),
      success_execution_entry("node-2", "code", 2),
      execution_entry(node_id: "node-2", node_type: "code", status: "failure", error: long_value),
      success_execution_entry("node-2", "code", 4),
      success_execution_entry("node-2", "code", 5),
      execution_entry(node_id: "node-3", node_type: "output", status: "skip"),
    ]
  end

  def success_execution_entry(node_id, node_type, step)
    execution_entry(
      node_id:,
      node_type:,
      status: "success",
      input: { "step" => step },
      output: { "ok" => true },
    )
  end

  def full_detail_execution_state(long_error)
    {
      "node_outputs" => { "node-2" => { "summary" => "done" } },
      "execution_log" => [
        execution_entry(
          node_id: "node-2",
          node_type: "code",
          status: "failure",
          input: { "value" => "Ada" },
          output: {},
          started_at: nil,
          finished_at: nil,
          error: long_error,
        ),
      ],
    }
  end

  def expect_summary_output(result)
    expect(result).to include(
      "## Mission Run",
      "- status: running",
      "- current_node_id: node-2",
      "- successful_steps: 4",
      "- failed_steps: 1",
      "- skipped_steps: 1",
      "## Output Meta",
      "- earlier_steps_omitted: 1",
      "step 6: Output [output] status=skip",
      "(truncated)",
    )
    expect(result).not_to include("## Node Outputs")
    expect(result).not_to include("_output_meta")
  end

  def expect_full_detail_output(result)
    expect(result).to include(
      "## Error",
      "## Trigger Data",
      "None.",
      "## Visible Variables",
      "## Node Outputs",
      "### Step 1",
      "- node: Transform [code]",
      "- duration_ms: -",
      "- started_at: -",
      "- finished_at: -",
      "- error:",
      "(truncated)",
    )
    expect(result).not_to include("## Output Meta")
  end

  def execution_entry(node_id:, node_type:, status:, **attributes)
    {
      "node_id" => node_id,
      "node_type" => node_type,
      "status" => status,
      "input" => attributes.fetch(:input, {}),
      "output" => attributes.fetch(:output, {}),
      "next_port" => "default",
      "started_at" => attributes.fetch(:started_at, 2.minutes.ago.iso8601(3)),
      "finished_at" => attributes.fetch(:finished_at, 2.minutes.ago.iso8601(3)),
      "error" => attributes[:error],
    }
  end
end
