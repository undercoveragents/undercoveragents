# frozen_string_literal: true

module TestSuites
  class MissionAssertionService
    def self.call(test_case:, mission_run:)
      new(test_case:, mission_run:).call
    end

    def initialize(test_case:, mission_run:)
      @test_case = test_case
      @mission_run = mission_run
    end

    def call
      failures = []

      failures.concat(assert_status)
      failures.concat(assert_variables) if @test_case.expected_variables.present?

      {
        passed: failures.empty?,
        analysis: failures.empty? ? build_success_message : failures.join("\n"),
      }
    end

    private

    def assert_status
      expected = @test_case.expected_status
      actual = @mission_run.status

      return [] if actual == expected

      ["Status mismatch: expected \"#{expected}\" but got \"#{actual}\"."]
    end

    def assert_variables
      expected = @test_case.expected_variables
      actual = @mission_run.variables || {}

      if @test_case.exact?
        assert_exact_variables(expected, actual)
      else
        assert_partial_variables(expected, actual)
      end
    end

    def assert_exact_variables(expected, actual)
      failures = []

      expected.each do |key, expected_value|
        actual_value = actual[key]
        unless values_match?(expected_value, actual_value)
          failures << "Variable \"#{key}\": expected #{expected_value.inspect} but got #{actual_value.inspect}."
        end
      end

      extra_keys = actual.keys - expected.keys - internal_variable_keys
      failures << "Unexpected variables: #{extra_keys.join(", ")}." if extra_keys.any?

      failures
    end

    def assert_partial_variables(expected, actual)
      failures = []

      expected.each do |key, expected_value|
        unless actual.key?(key)
          failures << "Variable \"#{key}\" not found in output."
          next
        end

        actual_value = actual[key]
        unless values_match?(expected_value, actual_value)
          failures << "Variable \"#{key}\": expected #{expected_value.inspect} but got #{actual_value.inspect}."
        end
      end

      failures
    end

    def values_match?(expected, actual)
      normalize(expected) == normalize(actual)
    end

    def normalize(value)
      case value
      when Hash
        value.transform_keys(&:to_s).transform_values { |v| normalize(v) }
      when Array
        value.map { |v| normalize(v) }
      when Numeric
        value.to_f
      else
        value
      end
    end

    def internal_variable_keys
      ["_current_node_id", "_current_node_type", "_current_node_data", "_nesting_depth"]
    end

    def build_success_message
      parts = ["Status matched: \"#{@test_case.expected_status}\"."]

      if @test_case.expected_variables.present?
        count = @test_case.expected_variables.size
        mode = @test_case.exact? ? "exact" : "partial"
        parts << "All #{count} expected #{"variable".pluralize(count)} matched (#{mode} mode)."
      end

      parts.join(" ")
    end
  end
end
