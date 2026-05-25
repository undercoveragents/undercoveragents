# frozen_string_literal: true

module BuiltinTools
  class RuntimeContext
    Context = Data.define(:agent, :chat, :mission, :ui_context, :user, :tenant, :operation)
    MODEL_CLASS_NAMES = [
      "Operation",
      "Mission",
      "Agent",
      "Tool",
      "SkillCatalog",
      "Skill",
      "RagFlow",
      "TestSuite",
      "CostLimit",
    ].freeze
    CURRENT_OBJECT_SCOPE_BUILDERS = {
      "Operation" => :tenant_operations,
      "Mission" => :tenant_missions,
      "Agent" => :tenant_agents,
      "Tool" => :tenant_tools,
      "SkillCatalog" => :tenant_skill_catalogs,
      "Skill" => :tenant_skills,
      "RagFlow" => :tenant_rag_flows,
      "TestSuite" => :tenant_test_suites,
      "CostLimit" => :tenant_cost_limits,
    }.freeze

    def self.build(...)
      new(...).build
    end

    def initialize(agent: nil, parent_chat: nil, mission: nil, ui_context: nil)
      @agent = agent
      @parent_chat = parent_chat
      @mission = mission
      @ui_context = ui_context.is_a?(Hash) ? ui_context.deep_stringify_keys : nil
    end

    def build
      Context.new(
        agent: @agent,
        chat: @parent_chat,
        mission: @mission,
        ui_context: @ui_context,
        user: resolved_user,
        tenant: resolved_tenant,
        operation: resolved_operation,
      )
    end

    private

    def resolved_user
      @parent_chat&.user || Current.user
    end

    def resolved_tenant
      [
        resolved_user&.tenant,
        @mission&.operation&.tenant,
        @agent&.tenant,
        Current.tenant,
      ].compact.first
    end

    def resolved_operation
      @mission&.operation || operation_from_current_object || operation_from_ui_context || Current.operation
    end

    def operation_from_ui_context
      operation_payload = @ui_context&.dig("operation")
      return unless operation_payload.is_a?(Hash)

      tenant = resolved_tenant
      return unless tenant

      tenant.operations.find_by(id: operation_payload["id"]) ||
        tenant.operations.find_by(slug: operation_payload["slug"])
    end

    def operation_from_current_object
      record = current_object_record
      return unless record

      direct_record_operation(record) || related_record_operation(record)
    end

    def direct_record_operation(record)
      return record if record.is_a?(Operation)
      return record.operation if record.respond_to?(:operation) && record.operation.present?

      nil
    end

    def related_record_operation(record)
      skill_catalog_operation(record) || test_suite_operation(record)
    end

    def skill_catalog_operation(record)
      return unless record.respond_to?(:skill_catalog)

      record.skill_catalog&.operation
    end

    def test_suite_operation(record)
      return unless record.is_a?(TestSuite)

      record.agent&.operation || record.mission&.operation
    end

    def current_object_record
      object = @ui_context&.dig("current_object")
      tenant = resolved_tenant
      return unless object.is_a?(Hash) && tenant

      scope = current_object_scope(current_object_class_name(object), tenant)
      scope && find_by_identifier(scope, object)
    end

    def current_object_class_name(object)
      object["class_name"].presence || model_class_names.find { |name| current_object_matches?(object, name) }
    end

    def current_object_matches?(object, model_name)
      model_class = model_name.safe_constantize
      return false unless model_class

      object["type"].to_s == model_class.model_name.human
    end

    def model_class_names
      MODEL_CLASS_NAMES
    end

    def current_object_scope(class_name, tenant)
      builder = CURRENT_OBJECT_SCOPE_BUILDERS[class_name]
      builder ? send(builder, tenant) : nil
    end

    def find_by_identifier(scope, object)
      scope.find_by(id: object["id"]) || scope.find_by(slug: object["slug"])
    end

    def tenant_operations(tenant) = tenant.operations

    def tenant_missions(tenant) = tenant.missions

    def tenant_agents(tenant) = tenant.agents

    def tenant_tools(tenant)
      Tool.joins(:operation).where(operations: { tenant_id: tenant.id })
    end

    def tenant_skill_catalogs(tenant)
      SkillCatalog.joins(:operation).where(operations: { tenant_id: tenant.id })
    end

    def tenant_skills(tenant)
      Skill.joins(skill_catalog: :operation).where(operations: { tenant_id: tenant.id })
    end

    def tenant_rag_flows(tenant)
      RagFlow.joins(:operation).where(operations: { tenant_id: tenant.id })
    end

    def tenant_test_suites(tenant) = tenant_scoped_test_suites(tenant)

    def tenant_cost_limits(tenant) = tenant.cost_limits

    def tenant_scoped_test_suites(tenant)
      TestSuite.where(agent_id: tenant.agents.select(:id))
               .or(TestSuite.where(mission_id: tenant.missions.select(:id)))
    end
  end
end
