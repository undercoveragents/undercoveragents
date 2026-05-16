# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
RSpec.describe TestSuiteDesigner do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }
  let(:agent_record) { create(:agent, operation:, name: "Support Agent", model_id: "gpt-4.1") }
  let(:mission_record) { create(:mission, operation:) }
  let(:lookup_harness_class) do
    Class.new do
      include TestSuiteDesigner::TestSuiteLookup
      include TestSuiteDesigner::TestCaseLookup
      include TestSuiteDesigner::TestSuiteRunLookup

      def initialize(runtime_context:, current_test_suite: nil)
        @runtime_context = runtime_context
        @current_test_suite = current_test_suite
      end

      def resolve_suite(test_suite_id = nil)
        send(:resolve_test_suite, test_suite_id)
      end

      def resolve_case(test_case_id = nil, test_suite: nil)
        send(:resolve_test_case, test_case_id, test_suite:)
      end

      def resolve_run(test_suite_run_id = nil, test_suite: nil)
        send(:resolve_test_suite_run, test_suite_run_id, test_suite:)
      end

      def call_private(name, *, **)
        send(name, *, **)
      end
    end
  end

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  def build_runtime_context(user: nil, chat: nil, ui_context: nil, tenant: nil, operation: nil)
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission: nil,
      ui_context:,
      user:,
      tenant:,
      operation:,
    )
  end

  describe TestSuiteDesigner::TestSuiteLookup do
    let(:test_suite) { create(:test_suite, agent: agent_record, name: "Lookup Suite") }

    it "resolves suites from the current object and explicit identifiers", :aggregate_failures do
      runtime_context = build_runtime_context(
        tenant:,
        operation:,
        ui_context: { "current_object" => { "class_name" => "TestSuite", "id" => test_suite.id } },
      )
      harness = lookup_harness_class.new(runtime_context:)

      expect(harness.resolve_suite).to eq(test_suite)
      expect(harness.resolve_suite(test_suite.id)).to eq(test_suite)
      expect(harness.resolve_suite(test_suite.slug)).to eq(test_suite)
    end

    it "resolves suites from page params and handles blank or missing ids", :aggregate_failures do
      runtime_context = build_runtime_context(
        tenant:,
        operation:,
        ui_context: { "page" => { "params" => { "test_suite_id" => test_suite.id.to_s } } },
      )
      harness = lookup_harness_class.new(runtime_context:)

      expect(harness.resolve_suite).to eq(test_suite)
      expect(harness.resolve_suite(" ")).to eq(test_suite)

      missing_context = build_runtime_context(tenant:, operation:)
      missing_harness = lookup_harness_class.new(runtime_context: missing_context)
      expect(missing_harness.resolve_suite(" ")).to be_nil
      expect { missing_harness.resolve_suite("missing-suite") }
        .to raise_error(ActiveRecord::RecordNotFound, /missing-suite/)
    end

    it "supports operation-scoped and empty fallback scopes", :aggregate_failures do
      allow(Tenant).to receive(:default_tenant).and_return(nil)

      operation_context = build_runtime_context(tenant: nil, operation:)
      operation_harness = lookup_harness_class.new(runtime_context: operation_context)
      expect(operation_harness.call_private(:test_suite_scope)).to include(test_suite)

      empty_context = build_runtime_context(tenant: nil, operation: nil)
      empty_harness = lookup_harness_class.new(runtime_context: empty_context)
      expect(empty_harness.call_private(:test_suite_scope)).to be_empty
    end

    it "falls back to the current suite target for tenant and operation lookup", :aggregate_failures do
      harness = lookup_harness_class.new(runtime_context: nil, current_test_suite: test_suite)

      expect(harness.call_private(:tenant)).to eq(tenant)
      expect(harness.call_private(:operation)).to eq(operation)
      expect(harness.call_private(:current_suite_tenant)).to eq(tenant)
      expect(harness.call_private(:current_suite_operation)).to eq(operation)
    end

    it "returns nil when resolving implicit suites without runtime context" do
      harness = lookup_harness_class.new(runtime_context: nil)

      expect(harness.resolve_suite(" ")).to be_nil
    end

    it "asks for an id or slug when a tenant-scoped suite name is ambiguous" do
      create(:test_suite, agent: agent_record, name: "Shared Suite")
      create(:test_suite, agent: create(:agent, operation: create(:operation, tenant:)), name: "Shared Suite")
      runtime_context = build_runtime_context(tenant:, operation: nil)
      harness = lookup_harness_class.new(runtime_context:)

      expect { harness.resolve_suite("Shared Suite") }
        .to raise_error(
          ActiveRecord::RecordNotFound,
          "Multiple test suites named 'Shared Suite' were found. Pass the numeric ID or slug instead.",
        )
    end
  end

  describe TestSuiteDesigner::TestCaseLookup do
    let(:test_suite) { create(:test_suite, agent: agent_record, name: "Case Lookup Suite") }
    let!(:test_case) { create(:test_case, test_suite:, prompt: "Lookup prompt", expected_answer: "Lookup answer") }

    it "resolves cases from the current object and by prompt", :aggregate_failures do
      runtime_context = build_runtime_context(
        tenant:,
        operation:,
        ui_context: { "current_object" => { "class_name" => "TestCase", "id" => test_case.id } },
      )
      harness = lookup_harness_class.new(runtime_context:, current_test_suite: test_suite)

      expect(harness.resolve_case(nil, test_suite:)).to eq(test_case)
      expect(harness.resolve_case(test_case.prompt, test_suite:)).to eq(test_case)
    end

    it "handles blank ids, global scope, and missing-case errors", :aggregate_failures do
      runtime_context = build_runtime_context(tenant:, operation:)
      harness = lookup_harness_class.new(runtime_context:, current_test_suite: test_suite)

      expect(harness.resolve_case(" ", test_suite:)).to be_nil
      expect(harness.call_private(:missing_test_case_message)).to include("No current test case")
      expect(harness.call_private(:test_case_scope, test_suite: nil)).to include(test_case)
      expect { harness.resolve_case("missing-case", test_suite:) }
        .to raise_error(ActiveRecord::RecordNotFound, /missing-case/)
    end

    it "returns nil for implicit case lookups without runtime context" do
      harness = lookup_harness_class.new(runtime_context: nil, current_test_suite: test_suite)

      expect(harness.resolve_case(nil, test_suite:)).to be_nil
    end
  end

  describe TestSuiteDesigner::TestSuiteRunLookup do
    let(:test_suite) { create(:test_suite, agent: agent_record, name: "Run Lookup Suite") }
    let!(:test_case) { create(:test_case, test_suite:) }
    let!(:test_suite_run) { create(:test_suite_run, test_suite:, status: :completed, total_count: 1) }
    let(:test_case_result) { create(:test_case_result, test_suite_run:, test_case:, status: :passed, passed: true) }

    it "resolves runs from the current object and exposes the global run scope", :aggregate_failures do
      test_case_result
      runtime_context = build_runtime_context(
        tenant:,
        operation:,
        ui_context: { "current_object" => { "class_name" => "TestSuiteRun", "id" => test_suite_run.id } },
      )
      harness = lookup_harness_class.new(runtime_context:, current_test_suite: test_suite)

      expect(harness.resolve_run(nil, test_suite:)).to eq(test_suite_run)
      expect(harness.call_private(:test_suite_run_scope, test_suite: nil)).to include(test_suite_run)
    end

    it "returns nil for blank ids and raises for missing runs", :aggregate_failures do
      runtime_context = build_runtime_context(tenant:, operation:)
      harness = lookup_harness_class.new(runtime_context:, current_test_suite: test_suite)

      expect(harness.resolve_run(" ", test_suite:)).to be_nil
      expect { harness.resolve_run("missing-run", test_suite:) }
        .to raise_error(ActiveRecord::RecordNotFound, /missing-run/)
    end

    it "returns nil for implicit run lookups without runtime context" do
      harness = lookup_harness_class.new(runtime_context: nil, current_test_suite: test_suite)

      expect(harness.resolve_run(nil, test_suite:)).to be_nil
    end
  end

  describe TestSuiteDesigner::ReadTestSuiteTool do
    let(:agent_suite) do
      create(:test_suite, agent: agent_record, name: "Read Agent Suite", evaluation_model_id: "gpt-4.1-mini")
    end

    it "authorizes when a user is present and reports unassigned, empty, and no-run states", :aggregate_failures do
      runtime_context = build_runtime_context(user:, tenant:, operation:)
      tool = described_class.new(runtime_context:, current_test_suite: agent_suite)

      expect(tool.execute).to include("Read Agent Suite")
      allow(agent_suite).to receive(:target).and_return(nil)
      expect(tool.send(:target_line, agent_suite)).to eq("Unassigned")
      expect(tool.send(:test_cases_section, agent_suite)).to eq("No test cases are defined yet.")
      expect(tool.send(:latest_run_section, agent_suite)).to eq("No runs have been recorded yet.")
    end

    it "reports mission-suite-specific test case fields", :aggregate_failures do
      mission_suite = create(:test_suite, :mission_suite, mission: mission_record, name: "Mission Read Suite")
      create(
        :test_case,
        :mission_case,
        test_suite: mission_suite,
        name: "Check completion",
        expected_status: "completed",
        input_variables: { "query" => "example" },
      )
      runtime_context = build_runtime_context(tenant:, operation:)
      tool = described_class.new(runtime_context:, current_test_suite: mission_suite)

      expect(tool.execute).to include("expected_status=`completed`", "input_keys=query")
    end

    it "returns authorization and generic errors", :aggregate_failures do
      runtime_context = build_runtime_context(user:, tenant:, operation:)
      tool = described_class.new(runtime_context:, current_test_suite: agent_suite)
      allow(tool).to receive(:authorize_policy!).and_raise(Pundit::NotAuthorizedError, "denied")
      expect(tool.execute).to eq("Error: denied")

      generic_tool = described_class.new(runtime_context:, current_test_suite: agent_suite)
      allow(generic_tool).to receive(:resolve_test_suite).and_raise(StandardError, "boom")
      expect(generic_tool.execute).to eq("Error reading test suite: boom")
    end

    it "reads suites when runtime context is nil" do
      tool = described_class.new(runtime_context: nil, current_test_suite: agent_suite)

      expect(tool.execute).to include("Read Agent Suite")
    end

    it "omits mission input keys when a mission case has no input variables", :aggregate_failures do
      mission_suite = create(:test_suite, :mission_suite, mission: mission_record, name: "Mission No Inputs")
      mission_case = build(:test_case, :mission_case, test_suite: mission_suite)
      mission_case.input_variables = {}
      tool = described_class.new(
        runtime_context: build_runtime_context(tenant:, operation:),
        current_test_suite: mission_suite,
      )

      expect(tool.send(:test_case_line, mission_case, test_suite: mission_suite)).not_to include("input_keys=")
    end
  end

  describe TestSuiteDesigner::ManageTestCaseTool do
    let(:agent_suite) { create(:test_suite, agent: agent_record, name: "Agent Manage Suite") }
    let(:mission_suite) { create(:test_suite, :mission_suite, mission: mission_record, name: "Mission Manage Suite") }
    let(:runtime_context) { build_runtime_context(user:, chat:, tenant:, operation:) }

    it "covers create and update validation errors and rescue paths", :aggregate_failures do
      tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: nil,
      )
      expect(tool.execute(action: "create", test_suite_id: " ", attributes: { prompt: "Q" }))
        .to include("No current test suite")

      blank_tool = described_class.new(runtime_context:, current_test_suite: agent_suite)
      expect(blank_tool.execute(action: "create", attributes: nil)).to eq("Error: Provide attributes for create.")

      test_case = create(:test_case, test_suite: agent_suite)
      expect(blank_tool.execute(action: "update", test_case_id: test_case.id, attributes: nil))
        .to eq("Error: Provide attributes for update.")
      expect(blank_tool.execute(action: "update", test_case_id: "missing", attributes: { prompt: "Q" }))
        .to include("Test case 'missing' was not found")
      expect(blank_tool.execute(action: "delete", test_case_id: "missing", confirm_destroy: true))
        .to include("Test case 'missing' was not found")

      nil_branch_tool = described_class.new(runtime_context:, current_test_suite: agent_suite)
      allow(nil_branch_tool).to receive(:resolve_test_case).and_return(nil)
      expect(nil_branch_tool.execute(action: "update", test_case_id: test_case.id, attributes: { prompt: "Q" }))
        .to eq(nil_branch_tool.send(:missing_test_case_message))
      expect(nil_branch_tool.execute(action: "delete", test_case_id: test_case.id, confirm_destroy: true))
        .to eq(nil_branch_tool.send(:missing_test_case_message))

      invalid_record = build(:test_case, test_suite: agent_suite)
      invalid_record.errors.add(:base, "invalid")
      allow(blank_tool).to receive(:create_test_case).and_raise(ActiveRecord::RecordInvalid.new(invalid_record))
      expect(blank_tool.execute(action: "create")).to eq("Error: invalid")

      error_tool = described_class.new(runtime_context:, current_test_suite: agent_suite)
      allow(error_tool).to receive(:create_test_case).and_raise(StandardError, "boom")
      expect(error_tool.execute(action: "create")).to eq("Error managing test case: boom")
    end

    it "covers mission-suite attribute assignment and normalization helpers", :aggregate_failures do
      tool = described_class.new(runtime_context:, current_test_suite: mission_suite)
      mission_case = build(:test_case, :mission_case, test_suite: mission_suite)

      tool.send(
        :assign_test_case_attributes!,
        mission_case,
        {
          "name" => "Coverage case",
          "input_variables" => '{"query":"value"}',
          "expected_variables" => '{"result":"done"}',
        },
      )
      expect(mission_case.input_variables).to eq({ "query" => "value" })
      expect(mission_case.expected_variables).to eq({ "result" => "done" })

      input_only_case = build(:test_case, :mission_case, test_suite: mission_suite)
      input_only_case.expected_variables = {}
      tool.send(:assign_test_case_attributes!, input_only_case, { "input_variables" => { query: "value" } })
      expect(input_only_case.expected_variables).to eq({})

      expected_only_case = build(:test_case, :mission_case, test_suite: mission_suite)
      expected_only_case.input_variables = {}
      tool.send(:assign_test_case_attributes!, expected_only_case, { "expected_variables" => { result: "done" } })
      expect(expected_only_case.input_variables).to eq({})

      expect(tool.send(:normalize_attributes, nil)).to eq({})
      expect(tool.send(:normalize_attributes, '{"prompt":"Q"}')).to eq({ "prompt" => "Q" })
      expect { tool.send(:normalize_attributes, 1) }
        .to raise_error(ArgumentError, "Attributes must be a hash or JSON object string.")
      expect { tool.send(:normalize_attributes, "[]") }
        .to raise_error(ArgumentError, "Attributes must be a JSON object.")

      expect(tool.send(:normalize_hash_attribute, nil)).to eq({})
      expect(tool.send(:normalize_hash_attribute, { result: "done" })).to eq({ "result" => "done" })
      expect(tool.send(:normalize_hash_attribute, '{"result":"done"}')).to eq({ "result" => "done" })
      expect { tool.send(:normalize_hash_attribute, 1) }
        .to raise_error(ArgumentError, "Hash attributes must be a hash or JSON object string.")
      expect { tool.send(:normalize_hash_attribute, "[]") }
        .to raise_error(ArgumentError, "Hash attributes must be a JSON object.")
    end

    it "covers the no-refresh success message paths", :aggregate_failures do
      tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: agent_suite,
      )
      test_case = create(:test_case, test_suite: agent_suite, prompt: "Delete me")

      expect(tool.send(:test_case_success_message, test_case:, action: "update", refreshed: false))
        .not_to include("Current page refresh started")
      expect(tool.execute(action: "delete", test_case_id: test_case.id, confirm_destroy: true))
        .not_to include("Current page refresh started")
    end
  end

  describe TestSuiteDesigner::ManageTestSuiteActionTool do
    let(:agent_suite) { create(:test_suite, agent: agent_record, name: "Action Suite") }
    let!(:test_case) { create(:test_case, test_suite: agent_suite, prompt: "Run me") }

    it "covers missing suite and case paths plus generic rescue handling", :aggregate_failures do
      tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: nil,
      )
      expect(tool.execute(action: "run_suite", test_suite_id: " ")).to include("No current test suite")
      expect(tool.execute(action: "run_test", test_suite_id: agent_suite.id, test_case_id: "missing"))
        .to include("Test case 'missing' was not found")

      nil_suite_tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: agent_suite,
      )
      allow(nil_suite_tool).to receive(:resolve_test_suite).and_return(nil)
      expect(nil_suite_tool.execute(action: "run_test", test_case_id: test_case.id))
        .to include("No current test suite")

      nil_case_tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: agent_suite,
      )
      allow(nil_case_tool).to receive(:resolve_test_case).and_return(nil)
      expect(nil_case_tool.execute(action: "run_test", test_case_id: test_case.id))
        .to eq(nil_case_tool.send(:missing_test_case_message))

      error_tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: agent_suite,
      )
      allow(error_tool).to receive(:run_suite).and_raise(StandardError, "boom")
      expect(error_tool.execute(action: "run_suite")).to eq("Error managing test suite action: boom")
    end

    it "covers record-invalid and argument-error rescue handling", :aggregate_failures do
      tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: agent_suite,
      )
      invalid_run = build(:test_suite_run, test_suite: agent_suite)
      invalid_run.errors.add(:base, "invalid")
      allow(tool).to receive(:run_suite).and_raise(ActiveRecord::RecordInvalid.new(invalid_run))
      expect(tool.execute(action: "run_suite")).to eq("Error: invalid")

      argument_tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: agent_suite,
      )
      allow(argument_tool).to receive(:run_test).and_raise(ArgumentError, "bad input")
      expect(argument_tool.execute(action: "run_test", test_case_id: test_case.id)).to eq("Error: bad input")
    end

    it "covers successful run summaries without failures and without refresh text", :aggregate_failures do
      tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: agent_suite,
      )
      allow(TestSuiteExecutionJob).to receive(:perform_now) do |run_id, **|
        run = TestSuiteRun.find(run_id)
        run.test_case_results.first.update!(status: :passed, passed: true, actual_answer: "24 hours")
        run.update!(status: :completed, completed_at: Time.current, passed_count: 1, failed_count: 0, error_count: 0)
      end

      result = tool.execute(action: "run_suite")
      expect(result).to include("All selected tests passed.")
      expect(result).not_to include("Current page refresh started")
    end

    it "covers inactive runs and preview metadata branches", :aggregate_failures do
      archived_suite = create(:test_suite, :archived, agent: agent_record, name: "Archived Action Suite")
      archived_case = create(:test_case, test_suite: archived_suite)
      archived_tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: archived_suite,
      )
      expect(archived_tool.execute(action: "run_test", test_case_id: archived_case.id))
        .to include("cannot run because it is archived")

      mission_run = create(:mission_run, mission: mission_record)
      result_with_metadata = build(
        :test_case_result,
        test_suite_run: build(:test_suite_run, test_suite: agent_suite),
        test_case:,
        status: :failed,
        analysis: "Mismatch",
        chat: create(:chat, :test_context),
        mission_run:,
      )
      preview_line = archived_tool.send(:failure_preview_line, result_with_metadata)
      expect(preview_line).to include("analysis=\"Mismatch\"", "chat_id=", "mission_run_id=")

      no_analysis_result = build(
        :test_case_result,
        test_suite_run: build(:test_suite_run, test_suite: archived_suite),
        test_case: archived_case,
        status: :error,
        analysis: nil,
      )
      expect(archived_tool.send(:failure_preview_line, no_analysis_result)).not_to include("analysis=")

      success_run = build(
        :test_suite_run,
        test_suite: archived_suite,
        failed_count: 0,
        error_count: 0,
        passed_count: 1,
        total_count: 1,
      )
      success_summary = archived_tool.send(
        :run_summary,
        run: success_run,
        action: "run_suite",
        refreshed: false,
      )
      expect(success_summary).not_to include("Current page refresh started")
    end
  end

  describe TestSuiteDesigner::ReadTestSuiteRunTool do
    let(:agent_suite) { create(:test_suite, agent: agent_record, name: "Run Reader Suite") }
    let!(:agent_case) { create(:test_case, test_suite: agent_suite, prompt: "Prompt?", expected_answer: "Answer") }
    let!(:agent_run) do
      create(
        :test_suite_run,
        :completed,
        test_suite: agent_suite,
        total_count: 1,
        passed_count: 0,
        failed_count: 1,
        duration_ms: 2500,
      ).tap do |run|
        create(
          :test_case_result,
          :failed,
          test_suite_run: run,
          test_case: agent_case,
          analysis: "Mismatch",
          actual_answer: "Wrong",
          chat: create(:chat, :test_context),
        )
      end
    end

    it "covers missing-suite, missing-run, invalid-detail, and blank-user paths", :aggregate_failures do
      blank_user_context = build_runtime_context(user: nil, tenant:, operation:)
      expect(described_class.new(runtime_context: blank_user_context).execute).to include("No current test suite")

      tool = described_class.new(runtime_context: blank_user_context, current_test_suite: agent_suite)
      expect(tool.execute(selector: "recent", limit: 0)).to include("## Recent Test Suite Runs")

      missing_run_tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: agent_suite,
      )
      allow(missing_run_tool).to receive(:resolve_test_suite_run).and_return(nil)
      expect(missing_run_tool.execute(test_suite_run_id: 123)).to include("No test suite run with ID '123'")

      generic_tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: agent_suite,
      )
      allow(generic_tool).to receive(:resolve_test_suite).and_raise(StandardError, "boom")
      expect(generic_tool.execute).to eq("Error reading test suite runs: boom")

      invalid_detail_tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: agent_suite,
      )
      expect(invalid_detail_tool.execute(detail: "bogus")).to eq("Error: detail must be one of: summary, full.")
    end

    it "skips authorization when runtime context is nil" do
      tool = described_class.new(runtime_context: nil, current_test_suite: agent_suite)

      expect { tool.send(:authorize_show!, agent_run) }.not_to raise_error
    end

    it "covers the no-runs recent path and agent-result metadata output", :aggregate_failures do
      empty_suite = create(:test_suite, agent: agent_record, name: "Empty Reader Suite")
      empty_tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: empty_suite,
      )
      expect(empty_tool.execute(selector: "recent")).to eq("No test suite runs found for 'Empty Reader Suite'.")

      tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: agent_suite,
      )
      result = tool.execute(test_suite_run_id: agent_run.id, detail: "full")
      expect(result).to include("- Chat ID:", "- Analysis: Mismatch", "- Duration: 2500 ms")

      plain_result = build(
        :test_case_result,
        test_suite_run: build(:test_suite_run, test_suite: agent_suite),
        test_case: agent_case,
        status: :error,
        analysis: nil,
        actual_answer: nil,
      )
      result_lines = tool.send(
        :result_report_lines,
        build(:test_suite_run, test_suite: agent_suite),
        results: [plain_result],
        full: false,
      )
      expect(result_lines.join("\n")).not_to include("Analysis", "Actual Answer")
    end

    it "covers mission-suite full result reporting and JSON previews", :aggregate_failures do
      mission_suite = create(:test_suite, :mission_suite, mission: mission_record, name: "Mission Reader Suite")
      mission_case = create(
        :test_case,
        :mission_case,
        test_suite: mission_suite,
        expected_status: "completed",
        input_variables: { "query" => "mission input" },
        expected_variables: { "result" => "ok" },
      )
      mission_run = create(:mission_run, mission: mission_record)
      suite_run = create(
        :test_suite_run,
        :completed,
        test_suite: mission_suite,
        total_count: 1,
        passed_count: 0,
        failed_count: 1,
        duration_ms: 1200,
      )
      create(
        :test_case_result,
        :failed,
        test_suite_run: suite_run,
        test_case: mission_case,
        actual_status: "failed",
        actual_variables: { "result" => "bad" },
        mission_run:,
      )

      tool = described_class.new(
        runtime_context: build_runtime_context(user:, tenant:, operation:),
        current_test_suite: mission_suite,
      )
      result = tool.execute(test_suite_run_id: suite_run.id, detail: "full")

      expect(result).to include(
        "- Mission Run ID:",
        "- Expected Status: `completed`",
        "- Actual Status: `failed`",
        "- Input Variables:",
        "- Expected Variables:",
        "- Actual Variables:",
      )

      blank_mission_case = build(:test_case, :mission_case, test_suite: mission_suite)
      blank_mission_case.input_variables = {}
      blank_mission_case.expected_variables = {}
      blank_mission_result = build(
        :test_case_result,
        test_suite_run: build(:test_suite_run, test_suite: mission_suite),
        test_case: blank_mission_case,
        actual_status: nil,
        actual_variables: {},
      )
      full_blank_lines = tool.send(:mission_result_lines, blank_mission_case, blank_mission_result, full: true)
      expect(full_blank_lines.join("\n"))
        .not_to include("Actual Status", "Input Variables", "Expected Variables", "Actual Variables")

      summary_blank_lines = tool.send(:mission_result_lines, blank_mission_case, blank_mission_result, full: false)
      expect(summary_blank_lines).to eq(["- Expected Status: `#{blank_mission_case.expected_status}`"])
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
