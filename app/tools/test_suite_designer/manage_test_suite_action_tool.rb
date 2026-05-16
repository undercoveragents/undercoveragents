# frozen_string_literal: true

module TestSuiteDesigner
  class ManageTestSuiteActionTool < RubyLLM::Tool
    include CurrentPageRefreshable
    include PolicyAuthorizable
    include TestCaseLookup
    include TestSuiteLookup

    ACTIONS = {
      "run_suite" => :run_suite,
      "run_test" => :run_test,
    }.freeze
    FAILURE_PREVIEW_LIMIT = 3

    description "Run a full test suite or a single test synchronously and return the latest result summary."

    param :action,
          desc: "Test suite action to run: 'run_suite' or 'run_test'."

    param :test_suite_id,
          desc: "Optional numeric ID or slug. Omit to use the current test suite from page context.",
          required: false

    param :test_case_id,
          desc: "Required for run_test. Accepts a numeric ID or exact case name/prompt.",
          required: false

    def initialize(runtime_context:, current_test_suite: nil)
      super()
      @runtime_context = runtime_context
      @current_test_suite = current_test_suite
    end

    def name = "manage_test_suite_action"

    def execute(action:, test_suite_id: nil, test_case_id: nil)
      normalized_action = ACTIONS[action.to_s]
      return "Error: Unknown action '#{action}'. Use run_suite or run_test." unless normalized_action

      return run_suite(test_suite_id) if normalized_action == :run_suite

      run_test(test_suite_id, test_case_id)
    rescue ActiveRecord::RecordInvalid => e
      "Error: #{e.record.errors.full_messages.to_sentence}"
    rescue ActiveRecord::RecordNotFound, ArgumentError, Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error managing test suite action: #{e.message}"
    end

    private

    def run_suite(test_suite_id)
      test_suite = resolve_test_suite(test_suite_id)
      return missing_test_suite_message if test_suite.nil?

      authorize_policy!(test_suite, :run?, user: @runtime_context.user)
      return cannot_run_message(test_suite) unless test_suite.can_run?

      run = execute_run(test_suite)
      run_summary(run:, action: "run_suite", refreshed: broadcast_current_page_refresh?)
    end

    def run_test(test_suite_id, test_case_id)
      test_suite = resolve_test_suite(test_suite_id)
      return missing_test_suite_message if test_suite.nil?

      test_case = resolve_test_case(test_case_id, test_suite:)
      return missing_test_case_message if test_case.nil?

      authorize_policy!(test_suite, :run?, user: @runtime_context.user)
      return cannot_run_message(test_suite) unless test_suite.active?

      run = execute_run(test_suite, test_cases: [test_case])
      run_summary(run:, action: "run_test", refreshed: broadcast_current_page_refresh?)
    end

    def execute_run(test_suite, test_cases: nil)
      run = TestSuites::CreateRunService.call(test_suite, test_cases:, user: @runtime_context.user)
      run.update!(status: :running, started_at: Time.current)
      TestSuiteExecutionJob.perform_now(run.id, tenant_id: tenant.id)
      run.reload
    end

    def run_summary(run:, action:, refreshed:)
      lines = [
        "Test suite action completed.",
        "- Action: `#{action}`",
        "- Test suite: #{run.test_suite.name} (`#{run.test_suite.id}`)",
        "- Run: `#{run.id}`",
        "- Status: `#{run.status}`",
        run_counts_line(run),
      ]

      if run.failed_count.zero? && run.error_count.zero?
        lines << "- Result: All selected tests passed."
      else
        lines << "## Failing Results"
        lines.concat(failure_preview_lines(run))
        lines << "- Use `read_test_suite_run(test_suite_run_id: #{run.id}, detail: \"full\")` for full details."
      end

      lines << "Current page refresh started to show the saved test suite." if refreshed
      lines.join("\n")
    end

    def failure_preview_lines(run)
      failing_results(run).map { |result| failure_preview_line(result) }
    end

    def resolved_test_case_label(test_case)
      test_case.display_label.presence || "Test case ##{test_case.id}"
    end

    def cannot_run_message(test_suite)
      "Error: Test suite '#{test_suite.name}' cannot run because it is archived or has no test cases."
    end

    def run_counts_line(run)
      "- Counts: total=#{run.total_count} passed=#{run.passed_count} " \
        "failed=#{run.failed_count} errors=#{run.error_count}"
    end

    def failing_results(run)
      run.test_case_results.includes(:test_case)
         .where(status: [:failed, :error])
         .limit(FAILURE_PREVIEW_LIMIT)
    end

    def failure_preview_line(result)
      failure_preview_parts(result).join(" — ")
    end

    def failure_preview_parts(result)
      parts = [
        "- `#{result.test_case_id}`",
        resolved_test_case_label(result.test_case),
        "status=`#{result.status}`",
      ]
      parts << "analysis=#{result.analysis.to_s.truncate(160).inspect}" if result.analysis.present?
      parts << "chat_id=`#{result.chat_id}`" if result.chat_id.present?
      parts << "mission_run_id=`#{result.mission_run_id}`" if result.mission_run_id.present?
      parts
    end
  end
end
