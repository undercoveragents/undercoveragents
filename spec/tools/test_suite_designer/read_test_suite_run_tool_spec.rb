# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuiteDesigner::ReadTestSuiteRunTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:agent_record) { create(:agent, operation:, model_id: "gpt-4.1") }
  let(:test_suite) { create(:test_suite, agent: agent_record, name: "Regression Smoke") }
  let!(:test_case) do
    create(:test_case, test_suite:, prompt: "What is our SLA?", expected_answer: "24 hours", match_type: "exact")
  end
  let!(:older_run) do
    create(
      :test_suite_run,
      test_suite:,
      status: :completed,
      total_count: 1,
      passed_count: 1,
      created_at: 2.minutes.ago,
      completed_at: 2.minutes.ago,
    ).tap do |run|
      create(:test_case_result, test_suite_run: run, test_case:, status: :passed, passed: true, analysis: "Looks good")
    end
  end
  let!(:latest_run) do
    create(
      :test_suite_run,
      test_suite:,
      status: :completed,
      total_count: 1,
      passed_count: 0,
      failed_count: 1,
      created_at: 1.minute.ago,
      completed_at: 1.minute.ago,
    ).tap do |run|
      create(
        :test_case_result,
        test_suite_run: run,
        test_case:,
        status: :failed,
        passed: false,
        analysis: "Expected exact match but answers differ.",
        actual_answer: "48 hours",
      )
    end
  end
  let(:runtime_context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: nil,
      user:,
      tenant:,
      operation:,
    )
  end
  let(:tool) { described_class.new(runtime_context:, current_test_suite: test_suite) }

  describe "#name" do
    it "returns read_test_suite_run" do
      expect(tool.name).to eq("read_test_suite_run")
    end
  end

  describe "#execute" do
    it "returns the latest run by default" do
      result = tool.execute

      expect(result).to include(
        "Run ID: `#{latest_run.id}`",
        "Status: `completed`",
        "## Failing Results",
        "Expected exact match but answers differ.",
      )
    end

    it "reads a specific run by id" do
      result = tool.execute(test_suite_run_id: older_run.id)

      expect(result).to include("Run ID: `#{older_run.id}`", "All recorded results passed.")
    end

    it "lists recent runs" do
      result = tool.execute(selector: "recent", limit: 2)

      expect(result).to include(
        "## Recent Test Suite Runs (2)",
        "run_id=`#{latest_run.id}` status=completed",
        "run_id=`#{older_run.id}` status=completed",
      )
    end

    it "returns full result details when requested" do
      result = tool.execute(test_suite_run_id: latest_run.id, detail: "full")

      expect(result).to include(
        "## Results",
        "### Test Case `#{test_case.id}`",
        "Prompt:",
        "Expected Answer:",
        "Actual Answer:",
      )
    end

    it "returns behavior evidence and debug snapshots for full agent details" do
      latest_run.test_case_results.first.update!(
        semantic_passed: true,
        behavior_passed: false,
        behavior_analysis: "Missing tool call.",
        actual_tool_names: ["list_resources"],
        actual_child_builtin_keys: ["agent_designer"],
        debug_snapshot: { "chat_id" => 123 },
      )

      result = tool.execute(test_suite_run_id: latest_run.id, detail: "full")

      expect(result).to include(
        "Semantic Passed: `true`",
        "Behavior Passed: `false`",
        "Behavior Analysis: Missing tool call.",
        "Tool Calls: list_resources",
        "Child Builtins: agent_designer",
        "Debug Snapshot:",
      )
    end

    # rubocop:disable RSpec/ExampleLength
    it "returns full mission result details" do
      mission = create(:mission, operation:)
      mission_suite = create(:test_suite, :mission_suite, mission:)
      mission_case = create(
        :test_case,
        :mission_case,
        test_suite: mission_suite,
        input_variables: { "ticket_id" => "123" },
        expected_variables: { "status" => "open" },
      )
      mission_run = create(:test_suite_run, test_suite: mission_suite, status: :completed, total_count: 1)
      create(
        :test_case_result,
        test_suite_run: mission_run,
        test_case: mission_case,
        status: :failed,
        actual_status: "failed",
        actual_variables: { "status" => "closed" },
      )

      result = described_class.new(runtime_context:, current_test_suite: mission_suite)
                              .execute(test_suite_run_id: mission_run.id, detail: "full")

      expect(result).to include(
        "Input Variables:",
        "Expected Variables:",
        "Actual Variables:",
        "Actual Status: `failed`",
      )
    end
    # rubocop:enable RSpec/ExampleLength

    it "returns a helpful message when no runs exist" do
      test_suite.test_suite_runs.destroy_all

      expect(tool.execute).to eq("No test suite runs found for 'Regression Smoke'.")
    end

    it "rejects unknown selectors" do
      expect(tool.execute(selector: "bogus")).to eq("Error: selector must be one of: latest, recent.")
    end
  end
end
