# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuiteDesigner::ManageTestSuiteActionTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }
  let(:agent_record) { create(:agent, operation:, model_id: "gpt-4.1") }
  let(:test_suite) { create(:test_suite, agent: agent_record, name: "Regression Smoke") }
  let!(:test_case) do
    create(:test_case, test_suite:, prompt: "What is our SLA?", expected_answer: "24 hours", match_type: "exact")
  end

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(TestSuiteExecutionJob).to receive(:perform_now) do |run_id, **|
      run = TestSuiteRun.find(run_id)
      result = run.test_case_results.first

      result.update!(status: :failed, analysis: "Expected exact match but answers differ.", actual_answer: "48 hours")
      run.update!(status: :completed, completed_at: Time.current, failed_count: 1, passed_count: 0, error_count: 0)
    end
  end

  def runtime_context_for(path:, current_object:)
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission: nil,
      ui_context: {
        "page" => { "path" => path },
        "current_object" => current_object,
      },
      user:,
      tenant:,
      operation:,
    )
  end

  def build_suite_tool
    context = runtime_context_for(
      path: Rails.application.routes.url_helpers.admin_test_suite_path(test_suite),
      current_object: { "class_name" => "TestSuite", "id" => test_suite.id },
    )

    described_class.new(runtime_context: context, current_test_suite: test_suite)
  end

  describe "#name" do
    it "returns manage_test_suite_action" do
      expect(build_suite_tool.name).to eq("manage_test_suite_action")
    end
  end

  describe "#execute" do
    it "runs the full suite synchronously and returns a failure preview" do
      result = build_suite_tool.execute(action: "run_suite")

      expect(result).to include(
        "Test suite action completed.",
        "Action: `run_suite`",
        "## Failing Results",
        "Expected exact match but answers differ.",
        "read_test_suite_run",
      )
      expect(TestSuiteExecutionJob).to have_received(:perform_now)
    end

    it "runs a single test synchronously" do
      result = build_suite_tool.execute(action: "run_test", test_case_id: test_case.id)

      run = TestSuiteRun.order(:id).last
      expect(result).to include("Action: `run_test`", "Run: `#{run.id}`")
      expect(run.total_count).to eq(1)
    end

    it "returns an error for unknown actions" do
      expect(build_suite_tool.execute(action: "archive")).to eq(
        "Error: Unknown action 'archive'. Use run_suite or run_test.",
      )
    end

    it "returns an error when the suite cannot run" do
      archived_suite = create(:test_suite, :archived, agent: agent_record, name: "Archived Suite")
      context = runtime_context_for(
        path: Rails.application.routes.url_helpers.admin_test_suite_path(archived_suite),
        current_object: { "class_name" => "TestSuite", "id" => archived_suite.id },
      )
      tool = described_class.new(runtime_context: context, current_test_suite: archived_suite)

      expect(tool.execute(action: "run_suite")).to eq(
        "Error: Test suite 'Archived Suite' cannot run because it is archived or has no test cases.",
      )
    end
  end
end
