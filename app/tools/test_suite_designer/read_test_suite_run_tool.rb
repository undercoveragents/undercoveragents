# frozen_string_literal: true

module TestSuiteDesigner
  class ReadTestSuiteRunTool < RubyLLM::Tool
    include PolicyAuthorizable
    include TestSuiteLookup
    include TestSuiteRunLookup

    RECENT_DEFAULT_LIMIT = RESULT_PREVIEW_LIMIT = 5

    description "Read one test suite run or list recent runs for the current test suite."

    param :test_suite_id,
          desc: "Optional numeric ID or slug. Omit to use the current test suite from page context.",
          required: false

    param :test_suite_run_id,
          desc: "Optional run ID. Omit to read the latest run or pass selector: 'recent'.",
          required: false

    param :selector,
          desc: "Optional selector. Use 'latest' (default) or 'recent'.",
          required: false

    param :limit,
          desc: "Optional limit for selector='recent'. Defaults to 5 and is capped at 10.",
          required: false

    param :detail,
          desc: "Optional detail level. Use 'summary' (default) or 'full'.",
          required: false

    def initialize(runtime_context:, current_test_suite: nil, current_test_suite_run: nil)
      super()
      @runtime_context = runtime_context
      @current_test_suite = current_test_suite
      @current_test_suite_run = current_test_suite_run
    end

    def name = "read_test_suite_run"

    def execute(test_suite_id: nil, test_suite_run_id: nil, selector: nil, limit: nil, detail: nil)
      test_suite = resolve_test_suite(test_suite_id)
      return missing_test_suite_message if test_suite.nil?

      return read_specific_run(test_suite, test_suite_run_id, detail) if test_suite_run_id.present?

      authorize_show!(test_suite)
      read_selected_runs(test_suite, selector:, limit:, detail:)
    rescue ActiveRecord::RecordNotFound, ArgumentError, Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error reading test suite runs: #{e.message}"
    end

    private

    def read_selected_runs(test_suite, selector:, limit:, detail:)
      normalized_selector = normalize_selector(selector)
      normalized_detail = normalize_detail(detail)

      if normalized_selector == "latest"
        run = test_suite.test_suite_runs.recent.first
        return no_runs_message(test_suite) unless run

        return run_report(run, detail: normalized_detail)
      end

      recent_runs_report(test_suite, limit)
    end

    def read_specific_run(test_suite, test_suite_run_id, detail)
      run = resolve_test_suite_run(test_suite_run_id, test_suite:)
      return missing_run_message(test_suite, test_suite_run_id) if run.nil?

      authorize_show!(run)
      run_report(run, detail: normalize_detail(detail))
    end

    def authorize_show!(record)
      user = @runtime_context&.user
      return if user.blank?

      authorize_policy!(record, :show?, user:)
    end

    def recent_runs_report(test_suite, limit)
      runs = test_suite.test_suite_runs.recent.limit(normalize_limit(limit))
      return no_runs_message(test_suite) if runs.empty?

      [
        "## Recent Test Suite Runs (#{runs.size})",
        *runs.map do |run|
          "- run_id=`#{run.id}` status=#{run.status} total=#{run.total_count} " \
            "passed=#{run.passed_count} failed=#{run.failed_count} errors=#{run.error_count}"
        end,
      ].join("\n")
    end

    def run_report(run, detail:)
      [run_header_lines(run), run_results_section(run, detail:)].flatten.join("\n")
    end

    def result_report_lines(run, results:, full:)
      suite = run.test_suite

      results.flat_map do |result|
        test_case = result.test_case
        lines = [
          "### Test Case `#{test_case.id}`",
          "- Label: #{test_case.display_label.presence || "Test case ##{test_case.id}"}",
          "- Status: `#{result.status}`",
          ("- Analysis: #{result.analysis}" if result.analysis.present?),
          ("- Chat ID: `#{result.chat_id}`" if result.chat_id.present?),
          ("- Mission Run ID: `#{result.mission_run_id}`" if result.mission_run_id.present?),
        ].compact

        if suite.agent?
          lines.concat(agent_result_lines(test_case, result, full:))
        else
          lines.concat(mission_result_lines(test_case, result, full:))
        end

        lines
      end
    end

    def agent_result_lines(test_case, result, full:)
      lines = []
      lines.concat(agent_expected_lines(test_case)) if full
      lines.concat(agent_evidence_lines(result))
      lines.concat(agent_behavior_lines(result))
      lines << "- Debug Snapshot: #{json_preview(result.debug_snapshot)}" if full && result.debug_snapshot.present?
      lines
    end

    def agent_expected_lines(test_case)
      [
        "- Prompt: #{test_case.prompt.to_s.truncate(240)}",
        "- Expected Answer: #{test_case.expected_answer.to_s.truncate(240)}",
      ]
    end

    def agent_evidence_lines(result)
      [
        ("- Actual Answer: #{result.actual_answer.to_s.truncate(240)}" if result.actual_answer.present?),
        ("- Tool Calls: #{result.actual_tool_names.join(", ")}" if result.actual_tool_names.any?),
        ("- Child Builtins: #{result.actual_child_builtin_keys.join(", ")}" if result.actual_child_builtin_keys.any?),
      ].compact
    end

    def agent_behavior_lines(result)
      [
        ("- Semantic Passed: `#{result.semantic_passed}`" unless result.semantic_passed.nil?),
        ("- Behavior Passed: `#{result.behavior_passed}`" unless result.behavior_passed.nil?),
        ("- Behavior Analysis: #{result.behavior_analysis}" if behavior_analysis_visible?(result)),
      ].compact
    end

    def behavior_analysis_visible?(result)
      result.behavior_analysis.present? && !result.behavior_passed?
    end

    def mission_result_lines(test_case, result, full:)
      lines = []
      lines << "- Expected Status: `#{test_case.expected_status}`"
      lines << "- Actual Status: `#{result.actual_status}`" if result.actual_status.present?
      if full
        lines << "- Input Variables: #{json_preview(test_case.input_variables)}" if test_case.input_variables.present?
        if test_case.expected_variables.present?
          lines << "- Expected Variables: #{json_preview(test_case.expected_variables)}"
        end
        lines << "- Actual Variables: #{json_preview(result.actual_variables)}" if result.actual_variables.present?
      end
      lines
    end

    def run_header_lines(run)
      [
        "## Test Suite Run",
        "- Test suite: #{run.test_suite.name} (`#{run.test_suite.id}`)",
        "- Run ID: `#{run.id}`",
        "- Status: `#{run.status}`",
        run_counts_line(run),
        ("- Duration: #{run.duration_ms} ms" if run.duration_ms.present?),
      ].compact
    end

    def run_results_section(run, detail:)
      return full_results_section(run) if detail == "full"

      failing_results = preview_failing_results(run)
      return ["All recorded results passed."] if failing_results.empty?

      ["## Failing Results", *result_report_lines(run, results: failing_results, full: false)]
    end

    def full_results_section(run)
      results = run.test_case_results.includes(:test_case).ordered
      ["## Results", *result_report_lines(run, results:, full: true)]
    end

    def preview_failing_results(run)
      run.test_case_results.includes(:test_case)
         .where(status: [:failed, :error])
         .limit(RESULT_PREVIEW_LIMIT)
    end

    def run_counts_line(run)
      "- Counts: total=#{run.total_count} passed=#{run.passed_count} " \
        "failed=#{run.failed_count} errors=#{run.error_count}"
    end

    def json_preview(value)
      JSON.pretty_generate(value).truncate(240)
    end

    def normalize_selector(selector)
      normalized = selector.to_s.presence || "latest"
      return normalized if ["latest", "recent"].include?(normalized)

      raise ArgumentError, "selector must be one of: latest, recent."
    end

    def normalize_detail(detail)
      normalized = detail.to_s.presence || "summary"
      return normalized if ["summary", "full"].include?(normalized)

      raise ArgumentError, "detail must be one of: summary, full."
    end

    def normalize_limit(limit)
      value = limit.to_i
      value = RECENT_DEFAULT_LIMIT if value <= 0
      [value, 10].min
    end

    def no_runs_message(test_suite)
      "No test suite runs found for '#{test_suite.name}'."
    end

    def missing_run_message(test_suite, test_suite_run_id)
      "No test suite run with ID '#{test_suite_run_id}' was found for '#{test_suite.name}'."
    end
  end
end
