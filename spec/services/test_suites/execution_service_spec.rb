# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuites::ExecutionService do
  let(:test_suite) { create(:test_suite, :with_test_cases) }
  let(:run) { TestSuites::CreateRunService.call(test_suite) }
  let(:agent) { test_suite.agent }

  let(:llm_response) { instance_double(RubyLLM::Message, content: "Test answer") }

  before do
    # Create a Model record matching the agent's model_id so Chat setup works
    create(:model, model_id: agent.model_id) unless Model.exists?(model_id: agent.model_id)

    # Stub the actual LLM HTTP call via Chat#ask (acts_as_chat delegates to RubyLLM)
    allow_any_instance_of(Chat).to receive(:ask).and_return(llm_response) # rubocop:disable RSpec/AnyInstance
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Rails.logger).to receive(:error)
  end

  describe ".call" do
    it "marks run as running then completed" do
      described_class.call(run)
      run.reload

      expect(run).to be_completed
      expect(run.started_at).to be_present
      expect(run.completed_at).to be_present
      expect(run.duration_ms).to be_present
    end

    it "preserves started_at when the run is already running" do
      existing_started_at = 5.seconds.ago.change(usec: 0)
      run.update!(status: :running, started_at: existing_started_at)

      test_suite.test_cases.reorder(nil).find_each do |tc|
        tc.update!(match_type: "exact", expected_answer: "test answer")
      end

      described_class.call(run)

      expect(run.reload.started_at.change(usec: 0)).to eq(existing_started_at)
      expect(run).to be_completed
    end

    it "executes all test cases" do
      described_class.call(run)

      run.test_case_results.reload.each do |result|
        expect(result.actual_answer).to eq("Test answer")
        expect(result.duration_ms).to be_present
      end
    end

    it "evaluates all test cases with exact match" do
      test_suite.test_cases.reorder(nil).find_each do |tc|
        tc.update!(match_type: "exact", expected_answer: "test answer")
      end
      described_class.call(run)

      run.test_case_results.reload.each do |result|
        expect(result).to be_passed
        expect(result.score).to eq(1.0)
        expect(result.completed_at).to be_present
      end
    end

    it "evaluates semantic matches via EvaluationService" do
      allow(TestSuites::EvaluationService).to receive(:call).and_return(
        { passed: true, score: 0.9, analysis: "Good match" },
      )

      described_class.call(run)

      run.test_case_results.reload.each do |result|
        expect(result).to be_passed
        expect(result.score).to eq(0.9)
        expect(result.analysis).to eq("Good match")
      end
    end

    it "marks result as failed when semantic evaluation does not pass" do
      allow(TestSuites::EvaluationService).to receive(:call).and_return(
        { passed: false, score: 0.2, analysis: "Answers differ significantly" },
      )

      described_class.call(run)

      run.test_case_results.reload.each do |result|
        expect(result).to be_failed
        expect(result.score).to eq(0.2)
      end
    end

    it "persists behavior check failures with semantic result details" do
      test_suite.test_cases.reorder(nil).find_each do |tc|
        tc.update!(match_type: "exact", expected_answer: "test answer")
      end
      test_suite.test_cases.first.update!(expected_tool_names: ["missing_tool"])

      described_class.call(run)

      result = run.test_case_results.find_by!(test_case: test_suite.test_cases.first)
      expect(result).to be_failed
      expect(result.semantic_passed).to be(true)
      expect(result.behavior_passed).to be(false)
      expect(result.behavior_analysis).to include("Missing expected tool calls")
      expect(result.actual_tool_names).to eq([])
    end

    it "keeps semantic analysis when behavior expectations pass" do
      test_case = test_suite.test_cases.first
      test_case.update!(match_type: "exact", expected_answer: "test answer", required_keywords: ["Test"])
      test_suite.test_cases.where.not(id: test_case.id).find_each do |tc|
        tc.update!(match_type: "exact", expected_answer: "test answer")
      end

      described_class.call(run)

      result = run.test_case_results.find_by!(test_case:)
      expect(result).to be_passed
      expect(result.analysis).to eq("Exact match confirmed.")
      expect(result.behavior_passed).to be(true)
    end

    it "cleans Agent Alpha fixture records after the test case is evaluated" do
      test_case = test_suite.test_cases.first
      test_case.update!(match_type: "exact", expected_answer: "test answer", fixture_key: "agent_alpha_benchmark")
      test_suite.test_cases.where.not(id: test_case.id).find_each do |tc|
        tc.update!(match_type: "exact", expected_answer: "test answer")
      end
      fixture = instance_double(
        TestSuites::AgentAlphaFixtureSet,
        render_context: {},
        runtime_context_for: {},
        runtime_context_summary: {},
        report_context: { "operation_id" => 123, "operation_name" => "AAB Fixture Operation" },
        operation: agent.operation,
        cleanup!: true,
      )
      allow(TestSuites::AgentAlphaFixtureSet).to receive(:build!).and_return(fixture)

      described_class.call(run)

      result = run.test_case_results.find_by!(test_case:)
      expect(fixture).to have_received(:cleanup!)
      expect(result.debug_snapshot.dig("fixture_cleanup", "status")).to eq("completed")
      expect(result.debug_snapshot.dig("fixture_cleanup", "records", "operation_id")).to eq(123)
    end

    it "marks the result as errored when fixture cleanup fails" do
      test_case = test_suite.test_cases.first
      test_case.update!(match_type: "exact", expected_answer: "test answer", fixture_key: "agent_alpha_benchmark")
      test_suite.test_cases.where.not(id: test_case.id).find_each do |tc|
        tc.update!(match_type: "exact", expected_answer: "test answer")
      end
      fixture = instance_double(
        TestSuites::AgentAlphaFixtureSet,
        render_context: {},
        runtime_context_for: {},
        runtime_context_summary: {},
        report_context: { "operation_id" => 123 },
        operation: agent.operation,
      )
      allow(fixture).to receive(:cleanup!).and_raise("cleanup exploded")
      allow(TestSuites::AgentAlphaFixtureSet).to receive(:build!).and_return(fixture)

      described_class.call(run)

      result = run.test_case_results.find_by!(test_case:)
      expect(result).to be_error
      expect(result.analysis).to include("Cleanup failed: cleanup exploded")
      expect(result.debug_snapshot.dig("fixture_cleanup", "status")).to eq("failed")
    end

    it "handles private utility branches", :aggregate_failures do
      service = described_class.new(run)
      parent_chat = create(:chat, :test_context, agent:)
      builtin_child_agent = build(:agent, operation: agent.operation, builtin: true)
      builtin_child_agent.builtin_key = "agent_designer"
      builtin_child_agent.save!
      create(:chat, :application_context, parent_chat:, agent: builtin_child_agent)
      create(:chat, :application_context, parent_chat:, agent: nil)
      bad_fixture = instance_double(
        TestSuites::AgentAlphaFixtureSet,
        report_context: {},
      )
      allow(bad_fixture).to receive(:cleanup!).and_raise("cleanup exploded")

      expect { service.send(:append_debug_snapshot!, nil, "ignored" => true) }.not_to raise_error
      expect { service.send(:cleanup_fixture_set, nil, bad_fixture) }.not_to raise_error
      expect(service.send(:collect_child_builtin_keys, parent_chat)).to eq(["agent_designer"])
      expect(service.send(:model_record_for_agent)).to eq(Model.find_by(model_id: agent.model_id))
      expect(service.send(:model_record_for_agent)).to eq(Model.find_by(model_id: agent.model_id))

      service.instance_variable_set(:@tenant, nil)
      expect(service.send(:default_user)).to be_nil
    end

    it "recovers non-hash debug snapshots when appending attributes" do
      service = described_class.new(run)
      result = run.test_case_results.first
      allow(result).to receive(:debug_snapshot).and_return("not-a-hash")
      allow(result).to receive(:update!)

      service.send(:append_debug_snapshot!, result, "recovered" => true)

      expect(result).to have_received(:update!).with(debug_snapshot: { "recovered" => true })
    end

    it "links chat records to test case results" do
      test_suite.test_cases.reorder(nil).find_each do |tc|
        tc.update!(match_type: "exact", expected_answer: "test answer")
      end
      described_class.call(run)

      run.test_case_results.reload.each do |result|
        expect(result.chat).to be_present
        expect(result.chat.execution_context).to eq("test")
      end
    end

    it "computes final counts" do
      test_suite.test_cases.reorder(nil).find_each do |tc|
        tc.update!(match_type: "exact", expected_answer: "test answer")
      end
      described_class.call(run)
      run.reload

      expect(run.passed_count).to eq(test_suite.test_cases.count)
      expect(run.failed_count).to eq(0)
      expect(run.error_count).to eq(0)
    end

    it "broadcasts header and status bar updates via Turbo Streams" do
      described_class.call(run)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with("test_suite_run_#{run.id}", hash_including(target: "test-run-header"))
        .at_least(:once)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with("test_suite_run_#{run.id}", hash_including(target: "test-run-status-bar"))
        .at_least(:once)
    end

    it "broadcasts individual result row updates" do
      described_class.call(run)

      run.test_case_results.each do |result|
        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
          .with("test_suite_run_#{run.id}", hash_including(target: "test-result-#{result.id}"))
          .at_least(:once)
      end
    end

    context "when a test case execution fails" do
      let(:test_suite) { create(:test_suite) }
      let(:run) { TestSuites::CreateRunService.call(test_suite) }
      let(:error_case) do
        create(:test_case, test_suite:, position: 0, match_type: "exact", expected_answer: "ok")
      end
      let(:ok_case) do
        create(:test_case, test_suite:, position: 1, match_type: "exact",
                           expected_answer: "test answer",)
      end

      before do
        error_case
        ok_case
      end

      it "marks the failed result as error but continues others" do
        call_count = 0
        allow_any_instance_of(Chat).to receive(:ask) do # rubocop:disable RSpec/AnyInstance
          call_count += 1
          raise StandardError, "LLM timeout" if call_count == 1

          instance_double(RubyLLM::Message, content: "Test answer")
        end

        described_class.call(run)

        results = run.test_case_results.reload
        error_results, non_error_results = results.partition(&:error?)

        expect(error_results.count).to eq(1)
        expect(non_error_results.count).to eq(1)
        expect(run.reload).to be_completed
      end
    end

    context "when all test cases fail" do
      before do
        allow_any_instance_of(Chat).to receive(:ask).and_raise(StandardError, "catastrophic failure") # rubocop:disable RSpec/AnyInstance
      end

      it "completes the run with all results as errors" do
        described_class.call(run)

        run.reload
        expect(run).to be_completed
        expect(run.test_case_results.reload).to all(be_error)
      end
    end
  end

  describe "cancellation" do
    it "skips test case processing when run is cancelled" do
      allow_any_instance_of(TestSuiteRun).to receive(:cancelled?).and_return(true) # rubocop:disable RSpec/AnyInstance

      described_class.call(run)

      run.test_case_results.reload.each do |result|
        expect(result.actual_answer).to be_nil
      end
    end
  end

  describe "build_test_chat branches" do
    context "when agent has no instructions" do
      let(:agent_no_instructions) do
        create(:agent, instructions: nil, model_id: agent.model_id)
      end
      let(:test_suite_no_instructions) do
        create(:test_suite, agent: agent_no_instructions)
      end
      let(:run_no_instructions) do
        create(:test_case, test_suite: test_suite_no_instructions, match_type: "exact",
                           expected_answer: "Test answer",)
        TestSuites::CreateRunService.call(test_suite_no_instructions)
      end

      it "does not call with_instructions when agent has no instructions" do
        expect_any_instance_of(Chat).not_to receive(:with_instructions) # rubocop:disable RSpec/AnyInstance

        described_class.call(run_no_instructions)
      end
    end

    context "when agent has tools" do
      before do
        connector = create(:connector, :sql_database, :enabled)
        sql_query = create(:tools_sql_query, connector:)
        tool = create(:tool, :enabled, toolable: sql_query)
        agent.update!(tool_ids: [tool.id])
      end

      it "calls with_tools when agent has enabled tools" do
        test_suite.test_cases.reorder(nil).find_each do |tc|
          tc.update!(match_type: "exact", expected_answer: "Test answer")
        end

        # The run should complete – with_tools branch is exercised
        described_class.call(run)

        run.reload
        expect(run).to be_completed
      end
    end
  end

  describe "fail_run! when start fails" do
    it "marks run as failed and handles nil started_at" do
      allow_any_instance_of(described_class).to receive(:start_run!).and_raise(StandardError, "DB connection failed") # rubocop:disable RSpec/AnyInstance

      expect { described_class.call(run) }.not_to raise_error

      run.reload
      expect(run).to be_failed
    end

    it "recomputes counts after unfinished results are marked as errors" do
      allow_any_instance_of(described_class).to receive(:execute_all_test_cases) do # rubocop:disable RSpec/AnyInstance
        results = run.test_case_results.reorder(nil).to_a
        results.first.update!(status: :passed, passed: true, completed_at: Time.current)
        results.second.update!(status: :running, started_at: Time.current)
        raise StandardError, "forced fail"
      end

      expect { described_class.call(run) }.not_to raise_error

      run.reload
      expect(run).to be_failed
      expect(run.passed_count).to eq(1)
      expect(run.error_count).to eq(run.total_count - 1)
      expect(run.test_case_results.reload.count(&:error?)).to eq(run.total_count - 1)
    end
  end

  describe "complete_run! with nil started_at" do
    it "handles nil started_at gracefully (duration_ms is nil)" do
      # Stub start_run! to be a no-op so started_at is never set
      allow_any_instance_of(described_class).to receive(:start_run!) # rubocop:disable RSpec/AnyInstance

      test_suite.test_cases.reorder(nil).find_each do |tc|
        tc.update!(match_type: "exact", expected_answer: "Test answer")
      end
      described_class.call(run)

      run.reload
      expect(run.duration_ms).to be_nil
    end
  end

  describe "evaluate_exact_match branches" do
    context "when exact match fails (is_match = false)" do
      it "marks result as failed with score 0.0 and non-match analysis" do
        test_suite.test_cases.reorder(nil).find_each do |tc|
          tc.update!(match_type: "exact", expected_answer: "expected different")
        end
        # LLM returns "Test answer" which downcased != "expected different"
        described_class.call(run)

        run.test_case_results.reload.each do |result|
          expect(result).to be_failed
          expect(result.score).to eq(0.0)
          expect(result.analysis).to include("Expected exact match but answers differ")
        end
      end
    end

    context "when fail_run! is called with a started_at present" do
      it "computes non-nil duration_ms" do
        allow_any_instance_of(described_class).to receive(:execute_all_test_cases) # rubocop:disable RSpec/AnyInstance
          .and_raise(StandardError, "forced fail")

        expect { described_class.call(run) }.not_to raise_error

        run.reload
        expect(run).to be_failed
        expect(run.duration_ms).not_to be_nil
      end
    end
  end

  describe "async execution" do
    it "processes cases concurrently without semaphore locking" do
      test_suite.test_cases.reorder(nil).find_each do |tc|
        tc.update!(match_type: "exact", expected_answer: "test answer")
      end

      described_class.call(run)

      expect(run.reload).to be_completed
      run.test_case_results.reload.each do |result|
        expect(result.completed_at).to be_present
      end
    end
  end
end
