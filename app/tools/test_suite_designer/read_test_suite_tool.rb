# frozen_string_literal: true

module TestSuiteDesigner
  class ReadTestSuiteTool < RubyLLM::Tool
    include PolicyAuthorizable
    include TestSuiteLookup

    TEST_CASE_ATTRIBUTE_KEYS = {
      "agent" => [
        "name",
        "prompt",
        "expected_answer",
        "match_type",
        "position",
        "scenario_key",
        "category",
        "complexity",
        "fixture_key",
        "expected_child_builtin_key",
        "expected_tool_names",
        "disallow_child_chats",
        "required_keywords",
        "forbidden_keywords",
      ],
      "mission" => ["name", "expected_status", "match_type", "position", "input_variables", "expected_variables"],
    }.freeze

    description "Inspect the current test suite, its test cases, latest run, and editable fields."

    param :test_suite_id,
          desc: "Optional numeric ID or slug. Omit to use the current test suite from page context.",
          required: false

    def initialize(runtime_context:, current_test_suite: nil)
      super()
      @runtime_context = runtime_context
      @current_test_suite = current_test_suite
    end

    def name = "read_test_suite"

    def execute(test_suite_id: nil)
      test_suite = resolve_test_suite(test_suite_id)
      return missing_test_suite_message if test_suite.nil?

      user = @runtime_context&.user
      authorize_policy!(test_suite, :show?, user:) if user.present?

      [
        "## Test Suite",
        suite_summary(test_suite),
        "## Test Cases",
        test_cases_section(test_suite),
        "## Latest Run",
        latest_run_section(test_suite),
        "## Editable Attribute Keys",
        editable_keys_section,
        "## Test Case Attribute Keys",
        test_case_keys_section(test_suite),
      ].join("\n")
    rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error reading test suite: #{e.message}"
    end

    private

    def suite_summary(test_suite)
      lines = [
        "- Name: #{test_suite.name}",
        "- ID: `#{test_suite.id}`",
        "- Type: `#{test_suite.suite_type}`",
        "- Status: `#{test_suite.status}`",
        "- Target: #{target_line(test_suite)}",
        "- Test cases: #{test_suite.test_case_count}",
      ]
      if test_suite.agent? && test_suite.resolved_evaluation_model_id.present?
        lines << "- Evaluation model: `#{test_suite.resolved_evaluation_model_id}`"
      end

      lines.join("\n")
    end

    def target_line(test_suite)
      target = test_suite.target
      return "Unassigned" unless target

      "#{target.name} (`#{target.id}`)"
    end

    def test_cases_section(test_suite)
      test_cases = test_suite.test_cases.ordered
      return "No test cases are defined yet." if test_cases.empty?

      test_cases.map { |test_case| test_case_line(test_case, test_suite:) }.join("\n")
    end

    def test_case_line(test_case, test_suite:)
      label = test_suite.agent? ? test_case.prompt.to_s.truncate(80) : test_case.name.to_s
      line = "- `#{test_case.id}` — #{label.presence || "(blank)"}"
      line << " match=`#{test_case.match_type}`"
      if test_suite.mission?
        line << " expected_status=`#{test_case.expected_status}`"
        keys = test_case.input_variables.keys
        line << " input_keys=#{keys.join(",")}" if keys.any?
      elsif test_case.behavior_expectations?
        line << " behavior=#{behavior_summary(test_case)}"
      end
      line
    end

    def behavior_summary(test_case)
      parts = []
      parts << "child=#{test_case.expected_child_builtin_key}" if test_case.expected_child_builtin_key.present?
      parts << "no_child_chats" if test_case.disallow_child_chats?
      parts << "tools=#{test_case.expected_tool_names.join(",")}" if test_case.expected_tool_names.any?
      parts << "required=#{test_case.required_keywords.join(",")}" if test_case.required_keywords.any?
      parts << "forbidden=#{test_case.forbidden_keywords.join(",")}" if test_case.forbidden_keywords.any?
      parts.join(";")
    end

    def latest_run_section(test_suite)
      latest_run = test_suite.latest_run
      return "No runs have been recorded yet." unless latest_run

      [
        "- Run: `#{latest_run.id}`",
        "- Status: `#{latest_run.status}`",
        latest_run_counts_line(latest_run),
        "- Use `read_test_suite_run(test_suite_run_id: #{latest_run.id}, detail: \"full\")` for full details.",
      ].join("\n")
    end

    def editable_keys_section
      [
        "- Use `manage_record(resource: \"test_suite\", ...)` for suite CRUD.",
        "- Supported suite attributes: #{quoted_keys(test_suite_permitted_attributes)}.",
      ].join("\n")
    end

    def test_case_keys_section(test_suite)
      keys = TEST_CASE_ATTRIBUTE_KEYS.fetch(test_suite.suite_type)

      [
        "- Use `manage_test_case` for nested test create, update, and delete actions.",
        "- Supported test case attributes: #{quoted_keys(keys)}.",
      ].join("\n")
    end

    def quoted_keys(keys)
      keys.map { |key| "`#{key}`" }.join(", ")
    end

    def latest_run_counts_line(latest_run)
      "- Counts: total=#{latest_run.total_count} passed=#{latest_run.passed_count} " \
        "failed=#{latest_run.failed_count} errors=#{latest_run.error_count}"
    end

    def test_suite_permitted_attributes
      RuntimeRecords::Registry.fetch("test_suite").permitted_attribute_keys
    end
  end
end
