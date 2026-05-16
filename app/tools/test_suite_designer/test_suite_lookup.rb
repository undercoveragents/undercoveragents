# frozen_string_literal: true

module TestSuiteDesigner
  module TestSuiteLookup
    private

    def resolve_test_suite(test_suite_id)
      current_suite = current_test_suite
      return current_suite if test_suite_id.blank? && current_suite.is_a?(TestSuite)

      identifier = test_suite_id.to_s.strip
      return nil if identifier.blank?

      scope = test_suite_scope
      scope.find_by(id: identifier) || scope.find_by(slug: identifier) ||
        unique_name_match(scope, identifier) || missing_test_suite!(identifier)
    end

    def unique_name_match(scope, identifier)
      matches = scope.where("LOWER(test_suites.name) = ?", identifier.downcase).limit(2).to_a
      return matches.first if matches.one?
      return nil if matches.empty?

      raise ActiveRecord::RecordNotFound,
            "Multiple test suites named '#{identifier}' were found. Pass the numeric ID or slug instead."
    end

    def current_test_suite
      return @current_test_suite if @current_test_suite.is_a?(TestSuite)

      suite_from_current_object || suite_from_page_param
    end

    def test_suite_scope
      scope = if tenant
                TestSuite.where(agent_id: tenant.agents.select(:id))
                         .or(TestSuite.where(mission_id: tenant.missions.select(:id)))
              elsif operation
                TestSuite.where(agent_id: operation.agents.select(:id))
                         .or(TestSuite.where(mission_id: operation.missions.select(:id)))
              else
                TestSuite.none
              end

      scope.includes(agent: :operation, mission: :operation).ordered
    end

    def missing_test_suite_message
      "No current test suite is available. Pass test_suite_id after creating one or open a test suite page first."
    end

    def missing_test_suite!(identifier)
      raise ActiveRecord::RecordNotFound, "Test suite '#{identifier}' was not found."
    end

    def test_suite_object?(object)
      object_matches?(object, TestSuite)
    end

    def suite_from_current_object
      ui_context = @runtime_context&.ui_context || {}
      object = ui_context["current_object"]
      return unless test_suite_object?(object)

      lookup_test_suite(object["id"]) || lookup_test_suite(object["slug"])
    end

    def suite_from_page_param
      ui_context = @runtime_context&.ui_context || {}
      identifier = ui_context.dig("page", "params", "test_suite_id").to_s.presence
      lookup_test_suite(identifier)
    end

    def lookup_test_suite(identifier)
      return if identifier.blank?

      scope = test_suite_scope
      scope.find_by(id: identifier) || scope.find_by(slug: identifier) || unique_name_match(scope, identifier)
    end

    def object_matches?(object, model_class)
      return false unless object.is_a?(Hash)

      [object["class_name"], object["type"]].compact.include?(model_class.name) ||
        [object["class_name"], object["type"]].compact.include?(model_class.model_name.human)
    end

    def tenant
      @runtime_context&.tenant || current_suite_tenant || Current.tenant || Tenant.default_tenant
    end

    def operation
      @runtime_context&.operation || current_suite_operation
    end

    def current_suite_tenant
      current_suite_operation&.tenant
    end

    def current_suite_operation
      @current_test_suite&.target&.operation
    end
  end
end
