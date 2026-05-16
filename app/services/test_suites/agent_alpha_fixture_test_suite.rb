# frozen_string_literal: true

module TestSuites
  module AgentAlphaFixtureTestSuite
    private

    def build_test_suite!
      suite = create_fixture_test_suite!
      fixture_test_case = create_fixture_test_case!(suite)
      run = create_fixture_test_suite_run!(suite)
      create_fixture_test_case_result!(run, fixture_test_case)
      suite
    end

    def create_fixture_test_suite!
      TestSuite.create!(
        name: render_context.fetch(:benchmark_test_suite_name),
        description: "Fixture test suite for #{scenario_key}",
        suite_type: "agent",
        agent:,
        evaluation_model_id: @model_id,
        evaluation_llm_connector: @llm_connector,
        evaluation_temperature: 0.2,
      )
    end

    def create_fixture_test_case!(suite)
      suite.test_cases.create!(
        prompt: "How do I request a refund?",
        expected_answer: "Share the charge details and ask support to review the refund request.",
        match_type: "semantic",
        position: 0,
      )
    end

    def create_fixture_test_suite_run!(suite)
      suite.test_suite_runs.create!(
        status: "completed",
        started_at: 2.minutes.ago,
        completed_at: 1.minute.ago,
        total_count: 1,
        passed_count: 1,
        failed_count: 0,
        error_count: 0,
        duration_ms: 1000,
      )
    end

    def create_fixture_test_case_result!(run, fixture_test_case)
      run.test_case_results.create!(
        test_case: fixture_test_case,
        status: "passed",
        passed: true,
        score: 1.0,
        analysis: "Fixture run passed.",
        actual_answer: fixture_test_case.expected_answer,
        started_at: run.started_at,
        completed_at: run.completed_at,
        duration_ms: 750,
      )
    end
  end
end
