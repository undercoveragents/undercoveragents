# frozen_string_literal: true

module ListResourcesToolScopeContext
  private

  def tenant = @runtime_context&.tenant || @mission&.operation&.tenant || Current.tenant || Tenant.default_tenant

  def scoped_operation
    @runtime_context&.operation || @mission&.operation || current_agent_operation_scope
  end

  def current_agent_operation_scope
    operation = @current_agent&.operation
    return operation unless fallback_to_default_operation_for_application_chat?(operation)

    tenant&.default_operation || operation
  end

  def fallback_to_default_operation_for_application_chat?(operation)
    operation&.headquarter? &&
      @current_agent&.builtin? &&
      @runtime_context&.chat&.application?
  end

  def tenant_scoped_test_suites
    TestSuite.where(agent_id: tenant.agents.select(:id))
             .or(TestSuite.where(mission_id: tenant.missions.select(:id)))
             .order(:name)
  end

  def test_suite_summary_line(test_suite, detail)
    line = "- `#{test_suite.id}` — #{test_suite.name}"
    detail.present? ? "#{line} (#{detail})" : line
  end
end
