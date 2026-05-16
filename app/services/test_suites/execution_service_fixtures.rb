# frozen_string_literal: true

module TestSuites
  module ExecutionServiceFixtures
    private

    def build_fixture_set(test_case)
      return unless test_case.fixture_key == self.class::AGENT_ALPHA_FIXTURE_KEY

      TestSuites::AgentAlphaFixtureSet.build!(
        tenant: @tenant,
        user: @user,
        test_case:,
        model_id: @agent.resolved_model_id,
        llm_connector: @agent.resolved_llm_connector,
        model_record: model_record_for_agent,
        token: "#{@run.id}-#{test_case.id}",
      )
    end

    def cleanup_fixture_set(result, fixture)
      return unless fixture

      fixture_context = fixture.report_context
      fixture.cleanup!
      append_debug_snapshot!(result, "fixture_cleanup" => { "status" => "completed", "records" => fixture_context })
    rescue StandardError => e
      handle_fixture_cleanup_error(result, e)
    end

    def handle_fixture_cleanup_error(result, error)
      Rails.logger.error "[TestSuites::ExecutionService] Fixture cleanup failed: #{error.message}"
      append_debug_snapshot!(result, "fixture_cleanup" => { "status" => "failed", "error" => error.message })
      return unless result&.persisted?

      result.update!(
        status: :error,
        passed: false,
        analysis: [result.analysis, "Cleanup failed: #{error.message}"].compact_blank.join(" | "),
        completed_at: Time.current,
      )
    end

    def append_debug_snapshot!(result, attributes)
      return unless result&.persisted?

      snapshot = result.debug_snapshot.is_a?(Hash) ? result.debug_snapshot.deep_dup : {}
      result.update!(debug_snapshot: snapshot.merge(attributes))
    end

    def debug_snapshot_for(test_case:, prompt:, expected_answer:, fixture:, chat:)
      {
        "test_case" => test_case_debug_snapshot(test_case),
        "prompt" => prompt,
        "expected_answer" => expected_answer,
        "fixture" => fixture&.report_context || {},
        "runtime_context" => fixture&.runtime_context_summary || {},
        "chat_id" => chat.id,
      }
    end

    def test_case_debug_snapshot(test_case)
      {
        "id" => test_case.id,
        "scenario_key" => test_case.scenario_key,
        "category" => test_case.category,
        "complexity" => test_case.complexity,
        "fixture_key" => test_case.fixture_key,
      }.compact
    end

    def with_current_context(fixture, &)
      Current.set(
        tenant: @tenant,
        operation: fixture&.operation || @agent.operation,
        user: @user,
        &
      )
    end
  end
end
