# frozen_string_literal: true

module TestSuiteDesigner
  module TestCaseLookup
    private

    def resolve_test_case(test_case_id, test_suite: nil)
      current_case = current_test_case(test_suite:)
      return current_case if test_case_id.blank? && current_case.is_a?(TestCase)

      identifier = test_case_id.to_s.strip
      return nil if identifier.blank?

      scope = test_case_scope(test_suite:)
      scope.find_by(id: identifier) || scope.find_by(name: identifier) || scope.find_by(prompt: identifier) ||
        missing_test_case!(identifier)
    end

    def current_test_case(test_suite: nil)
      ui_context = @runtime_context&.ui_context || {}
      object = ui_context["current_object"]
      return unless object_matches?(object, TestCase)

      test_case_scope(test_suite:).find_by(id: object["id"])
    end

    def test_case_scope(test_suite: nil)
      scope = TestCase.includes(:test_suite)
      scope = scope.where(test_suite_id: test_suite.id) if test_suite
      scope = scope.where(test_suite_id: test_suite_scope.select(:id)) if test_suite.nil?
      scope.ordered
    end

    def missing_test_case_message
      "No current test case is available. Pass test_case_id after creating one or list the suite test cases first."
    end

    def missing_test_case!(identifier)
      raise ActiveRecord::RecordNotFound, "Test case '#{identifier}' was not found."
    end
  end
end
