# frozen_string_literal: true

module TestSuiteDesigner
  module TestSuiteRunLookup
    private

    def resolve_test_suite_run(test_suite_run_id, test_suite: nil)
      current_run = current_test_suite_run(test_suite:)
      return current_run if test_suite_run_id.blank? && current_run.is_a?(TestSuiteRun)

      identifier = test_suite_run_id.to_s.strip
      return nil if identifier.blank?

      scope = test_suite_run_scope(test_suite:)
      scope.find_by(id: identifier) || missing_test_suite_run!(identifier)
    end

    def current_test_suite_run(test_suite: nil)
      ui_context = @runtime_context&.ui_context || {}
      object = ui_context["current_object"]
      return unless object_matches?(object, TestSuiteRun)

      test_suite_run_scope(test_suite:).find_by(id: object["id"])
    end

    def test_suite_run_scope(test_suite: nil)
      scope = TestSuiteRun.includes(:test_suite, test_case_results: :test_case)
      scope = scope.where(test_suite_id: test_suite.id) if test_suite
      scope = scope.where(test_suite_id: test_suite_scope.select(:id)) if test_suite.nil?
      scope.recent
    end

    def missing_test_suite_run!(identifier)
      raise ActiveRecord::RecordNotFound, "Test suite run '#{identifier}' was not found."
    end
  end
end
