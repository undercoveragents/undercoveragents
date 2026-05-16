# frozen_string_literal: true

module AgentAlpha
  class RuntimeContext
    CURRENT_RECORD_RESOLVERS = {
      mission: :resolve_current_mission,
      current_agent: :resolve_current_agent,
      current_channel: :resolve_current_channel,
      current_client: :resolve_current_client,
      current_tool: :resolve_current_tool,
      current_skill_catalog: :resolve_current_skill_catalog,
      current_skill: :resolve_current_skill,
      current_rag_flow: :resolve_current_rag_flow,
      current_connector: :resolve_current_connector,
      current_test_suite: :resolve_current_test_suite,
    }.freeze

    def self.build(ui_context:, tenant:)
      new(ui_context:, tenant:).build
    end

    def initialize(ui_context:, tenant:)
      @ui_context = ui_context&.deep_stringify_keys
      @tenant = tenant
    end

    def build
      {}.tap do |context|
        context[:ui_context] = @ui_context if @ui_context.present?
        context.merge!(resolved_current_records)
      end
    end

    private

    attr_reader :tenant

    def resolved_current_records
      CURRENT_RECORD_RESOLVERS.each_with_object({}) do |(key, resolver), context|
        record = send(resolver)
        context[key] = record if record.present?
      end
    end

    def resolve_current_mission
      resolve_current_record(Mission.joins(:operation).where(operations: { tenant_id: tenant&.id }), Mission)
    end

    def resolve_current_agent
      resolve_current_record(Agent.joins(:operation).where(operations: { tenant_id: tenant&.id }), Agent)
    end

    def resolve_current_channel
      resolve_current_record(Channel.where(tenant_id: tenant&.id), Channel)
    end

    def resolve_current_client
      resolve_current_record(Client.where(tenant_id: tenant&.id), Client)
    end

    def resolve_current_tool
      resolve_current_record(Tool.joins(:operation).where(operations: { tenant_id: tenant&.id }), Tool)
    end

    def resolve_current_skill_catalog
      resolve_current_record(
        SkillCatalog.joins(:operation).where(operations: { tenant_id: tenant&.id }),
        SkillCatalog,
      )
    end

    def resolve_current_skill
      resolve_current_record(
        Skill.joins(skill_catalog: :operation).where(operations: { tenant_id: tenant&.id }),
        Skill,
      )
    end

    def resolve_current_rag_flow
      resolve_current_record(RagFlow.joins(:operation).where(operations: { tenant_id: tenant&.id }), RagFlow)
    end

    def resolve_current_connector
      resolve_current_record(Connector.where(tenant_id: tenant&.id), Connector)
    end

    def resolve_current_test_suite
      resolve_current_record(tenant_scoped_test_suites, TestSuite) ||
        resolve_nested_current_test_suite(TestCase) ||
        resolve_nested_current_test_suite(TestSuiteRun)
    end

    def resolve_current_record(scope, *model_classes)
      object = current_object
      return unless current_object?(object, *model_classes)

      scope.find_by(id: object["id"]) || scope.find_by(slug: object["slug"])
    end

    def resolve_nested_current_test_suite(model_class)
      return unless tenant
      return unless current_object?(current_object, model_class)

      model_class.joins(:test_suite)
                 .where(test_suites: { id: tenant_scoped_test_suites.select(:id) })
                 .find_by(id: current_object["id"])
                 &.test_suite
    end

    def current_object?(object, *model_classes)
      return false unless object.is_a?(Hash)

      expected_values = model_classes.flat_map do |model_class|
        [model_class.name, model_class.model_name.human]
      end

      [object["class_name"], object["type"]].compact.intersect?(expected_values)
    end

    def current_object
      @ui_context&.dig("current_object")
    end

    def tenant_scoped_test_suites
      return TestSuite.none unless tenant

      TestSuite.where(agent_id: tenant.agents.select(:id))
               .or(TestSuite.where(mission_id: tenant.missions.select(:id)))
    end
  end
end
