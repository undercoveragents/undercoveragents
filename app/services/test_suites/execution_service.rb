# frozen_string_literal: true

require "async"

module TestSuites
  # Executes all test cases in a test suite run using Async fibers.
  class ExecutionService
    include ExecutionServiceBroadcasts
    include ExecutionServiceFixtures

    MAX_CONCURRENCY = 5
    AGENT_ALPHA_FIXTURE_KEY = "agent_alpha_benchmark"
    TestCaseExecution = Data.define(
      :test_case, :fixture, :render_context, :prompt, :expected_answer, :chat, :answer, :duration_ms,
      :tool_names, :child_builtin_keys,
    )

    def self.call(run)
      new(run).call
    end

    def initialize(run)
      @run = run
      @test_suite = run.test_suite
      @agent = @test_suite.agent
      @tenant = @test_suite.tenant
      @user = run.user || default_user
    end

    def call
      start_run!
      execute_all_test_cases
      complete_run!
    rescue StandardError => e
      Rails.logger.error "[TestSuites::ExecutionService] Run ##{@run.id} failed: #{e.message}"
      fail_run!(e)
    end

    private

    def start_run!
      unless @run.running? && @run.started_at.present?
        @run.update!(status: :running, started_at: @run.started_at || Time.current)
      end

      broadcast_run_update
    end

    def execute_all_test_cases
      results = @run.test_case_results.includes(:test_case).to_a

      Async do |task|
        results.each_slice(MAX_CONCURRENCY) do |batch|
          batch_tasks = batch.map do |result|
            task.async do
              process_test_case(result)
            end
          end

          batch_tasks.each(&:wait)
        end
      end
    end

    def process_test_case(result)
      test_case = result.test_case
      fixture = nil

      # Check cancellation before starting any work for this test case.
      # NOTE: in-flight LLM calls cannot be interrupted mid-stream once started;
      # this check only prevents new calls from beginning after cancellation.
      return if @run.reload.cancelled?

      mark_result_running(result)

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      fixture = build_fixture_set(test_case)
      execution = build_test_case_execution(test_case, fixture:, start_time:)
      persist_execution_result(result, execution)
      evaluate_result(result, execution)
    rescue StandardError => e
      handle_test_case_error(result, e)
    ensure
      cleanup_fixture_set(result, fixture)
    end

    def mark_result_running(result)
      result.update!(status: :running, started_at: Time.current)
      broadcast_result_update(result)
    end

    def build_test_case_execution(test_case, fixture:, start_time:)
      render_context = fixture&.render_context || {}
      prompt = test_case.rendered_prompt(render_context)
      expected_answer = test_case.rendered_expected_answer(render_context)
      chat = build_test_chat(test_case, fixture:)
      answer = ask_agent_with_chat(chat, prompt, fixture:)

      TestCaseExecution.new(
        test_case:, fixture:, render_context:, prompt:, expected_answer:, chat:, answer:,
        duration_ms: elapsed_ms_since(start_time), tool_names: collect_tool_names(chat),
        child_builtin_keys: collect_child_builtin_keys(chat),
      )
    end

    def elapsed_ms_since(start_time)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    end

    def persist_execution_result(result, execution)
      result.update!(
        actual_answer: execution.answer,
        actual_tool_names: execution.tool_names,
        actual_child_builtin_keys: execution.child_builtin_keys,
        duration_ms: execution.duration_ms,
        status: :evaluating,
        chat: execution.chat,
        debug_snapshot: debug_snapshot_for(
          test_case: execution.test_case, prompt: execution.prompt, expected_answer: execution.expected_answer,
          fixture: execution.fixture, chat: execution.chat,
        ),
      )
      broadcast_result_update(result)
    end

    def evaluate_result(result, execution)
      semantic = evaluate_semantic_result(result, execution)
      behavior = evaluate_behavior_for(result, execution)
      passed = semantic[:passed] && behavior.passed

      result.update!(
        passed:,
        score: semantic[:score],
        status: passed ? :passed : :failed,
        analysis: combined_analysis(execution.test_case, semantic:, behavior:),
        semantic_passed: semantic[:passed],
        behavior_passed: behavior.passed,
        behavior_analysis: behavior.analysis,
        completed_at: Time.current,
      )
      broadcast_result_update(result)
    end

    def evaluate_semantic_result(result, execution)
      return evaluate_exact_match(result, execution.expected_answer) if execution.test_case.exact?

      evaluate_semantic_match(
        result, execution.test_case,
        prompt: execution.prompt,
        expected_answer: execution.expected_answer,
      )
    end

    def evaluate_behavior_for(result, execution)
      evaluate_behavior(
        result,
        execution.test_case,
        render_context: execution.render_context,
        tool_names: execution.tool_names,
        child_builtin_keys: execution.child_builtin_keys,
      )
    end

    def ask_agent_with_chat(chat, prompt, fixture:)
      response = with_current_context(fixture) { chat.ask(prompt) }
      response.content
    end

    def build_test_chat(test_case, fixture:)
      model_record = model_record_for_agent

      chat = Chat.new(
        agent: @agent,
        model: model_record,
        user: @user,
        title: "Test: #{test_case.prompt.truncate(50)}",
        execution_context: :test,
      )

      chat.save!
      with_current_context(fixture) do
        chat.configure_for_agent(@agent, runtime_context: fixture&.runtime_context_for || {})
      end
      chat
    end

    def evaluate_exact_match(result, expected_answer)
      actual = result.actual_answer.to_s.strip.downcase
      expected = expected_answer.to_s.strip.downcase
      is_match = actual == expected

      {
        passed: is_match,
        score: is_match ? 1.0 : 0.0,
        analysis: is_match ? "Exact match confirmed." : "Expected exact match but answers differ.",
      }
    end

    def evaluate_semantic_match(result, _test_case, prompt:, expected_answer:)
      evaluation = TestSuites::EvaluationService.call(
        prompt:,
        expected: expected_answer,
        actual: result.actual_answer.to_s,
        test_suite: @test_suite,
        context: { parent_chat: result.chat },
      )

      {
        passed: evaluation[:passed],
        score: evaluation[:score],
        analysis: evaluation[:analysis],
      }
    end

    def evaluate_behavior(result, test_case, render_context:, tool_names:, child_builtin_keys:)
      return passing_behavior_result unless test_case.behavior_expectations?

      TestSuites::BehaviorEvaluator.call(
        test_case:,
        response: result.actual_answer.to_s,
        tool_names:,
        child_builtin_keys:,
        context: render_context,
      )
    end

    def passing_behavior_result
      TestSuites::BehaviorEvaluator::Result.new(
        passed: true,
        analysis: "Behavior checks passed.",
        details: [],
      )
    end

    def combined_analysis(test_case, semantic:, behavior:)
      analysis = semantic[:analysis].to_s
      return analysis if behavior.passed && !test_case.behavior_expectations?
      return analysis if behavior.passed

      [analysis, "Behavior: #{behavior.analysis}"].compact_blank.join(" | ")
    end

    def collect_tool_names(chat)
      chat.reload.messages.includes(:tool_calls).order(:created_at, :id).flat_map do |message|
        message.tool_calls.map(&:name)
      end.uniq
    end

    def collect_child_builtin_keys(chat)
      chat.reload.child_chats.includes(:agent).order(:created_at, :id).filter_map do |child|
        child.agent&.builtin_key
      end.uniq
    end

    def model_record_for_agent
      return @model_record_for_agent if defined?(@model_record_for_agent)

      @model_record_for_agent = Model.find_by(model_id: @agent.resolved_model_id)
    end

    def default_user
      return unless @tenant

      @tenant.users.where(role: ["admin", "system_admin"]).ordered.first || @tenant.users.ordered.first
    end

    def handle_test_case_error(result, error)
      Rails.logger.error "[TestSuites::ExecutionService] Test case ##{result.test_case_id} error: #{error.message}"
      result.update!(
        status: :error,
        analysis: "Error: #{error.message}",
        passed: false,
        completed_at: Time.current,
      )
      broadcast_result_update(result)
    end

    def complete_run!
      @run.compute_counts!
      elapsed = @run.started_at ? ((Time.current - @run.started_at) * 1000).round : nil
      @run.update!(
        status: :completed,
        completed_at: Time.current,
        duration_ms: elapsed,
      )
      broadcast_run_update
    end

    def fail_run!(error)
      @run.update!(
        status: :failed,
        completed_at: Time.current,
        duration_ms: @run.started_at ? ((Time.current - @run.started_at) * 1000).round : nil,
      )

      @run.test_case_results.where(status: [:pending, :running, :evaluating]).find_each do |result|
        result.update!(status: :error, passed: false, analysis: "Run failed: #{error.message}",
                       completed_at: Time.current,)
        broadcast_result_update(result)
      end

      @run.compute_counts!

      broadcast_run_update
    end
  end
end
