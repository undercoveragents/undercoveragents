# frozen_string_literal: true

module RuntimeRecords
  module RegistryTestSuiteResources
    private

    def register_test_suite
      register(
        "test_suite",
        label: "Test Suite",
        model_class: TestSuite,
        permitted_attributes: RuntimeRecords::TEST_SUITE_PERMITTED_ATTRIBUTES,
        scope_resolver: method(:test_suite_scope),
        base_attributes: {},
        default_page: "show",
        page_resolver: method(:test_suite_page_path),
        create_handler: method(:test_suite_create),
        update_handler: method(:test_suite_update),
      )
    end

    def test_suite_scope(context)
      tenant_test_suites(test_suite_tenant(context))
    end

    def test_suite_page_path(page, record:, context:)
      _context = context
      helpers = Rails.application.routes.url_helpers

      case page.to_s
      when "index"
        helpers.admin_test_suites_path
      when "new"
        helpers.new_admin_test_suite_path
      when "show"
        raise ArgumentError, "Test suite page 'show' requires a record." unless record

        helpers.admin_test_suite_path(record)
      when "edit"
        raise ArgumentError, "Test suite page 'edit' requires a record." unless record

        helpers.edit_admin_test_suite_path(record)
      else
        raise ArgumentError, "Unknown page '#{page}' for test_suite. Use index, new, show, or edit."
      end
    end

    def test_suite_create(context:, definition:, attributes:, authorize:, **)
      test_suite = definition.model_class.new(definition.base_attributes_for(context))
      assign_test_suite_attributes!(test_suite, attributes:, tenant: test_suite_tenant(context))
      authorize.call(test_suite, :create?)
      test_suite.save!
      test_suite
    end

    def test_suite_update(record:, attributes:, context:, **)
      assign_test_suite_attributes!(record, attributes:, tenant: test_suite_tenant(context))
      record.save!
      record
    end

    def test_suite_tenant(context)
      tenant = context.tenant || context.operation&.tenant
      raise ArgumentError, "No active tenant is available for test suites." unless tenant

      tenant
    end

    def assign_test_suite_attributes!(record, attributes:, tenant:)
      normalized_attributes = attributes.stringify_keys

      record.assign_attributes(
        normalized_attributes.slice(
          "name",
          "description",
          "evaluation_model_id",
          "evaluation_temperature",
        ),
      )

      assign_test_suite_target!(record, normalized_attributes, tenant:)
      assign_test_suite_connector!(record, normalized_attributes, tenant:)
    end

    def assign_test_suite_target!(record, attributes, tenant:)
      case resolve_test_suite_target_type(record, attributes)
      when "agent"
        assign_agent_test_suite_target!(record, attributes, tenant:)
      when "mission"
        assign_mission_test_suite_target!(record, attributes, tenant:)
      else
        raise ArgumentError, "Unknown suite_type '#{attributes["suite_type"]}'. Use agent or mission."
      end
    end

    def assign_agent_test_suite_target!(record, attributes, tenant:)
      agent = resolve_test_suite_agent(attributes["agent_id"], tenant:) || record.agent
      raise ArgumentError, "Agent test suites require agent_id." unless agent

      record.suite_type = "agent"
      record.agent = agent
      record.mission = nil
    end

    def assign_mission_test_suite_target!(record, attributes, tenant:)
      mission = resolve_test_suite_mission(attributes["mission_id"], tenant:) || record.mission
      raise ArgumentError, "Mission test suites require mission_id." unless mission

      record.suite_type = "mission"
      record.mission = mission
      record.agent = nil
      record.evaluation_llm_connector = nil
      record.evaluation_model_id = nil
    end

    def resolve_test_suite_target_type(record, attributes)
      attributes["suite_type"].presence ||
        ("mission" if attributes["mission_id"].present?) ||
        ("agent" if attributes["agent_id"].present?) ||
        record.suite_type.presence ||
        "agent"
    end

    def assign_test_suite_connector!(record, attributes, tenant:)
      return if record.mission?
      return unless attributes.key?("evaluation_llm_connector_id")

      identifier = attributes["evaluation_llm_connector_id"].to_s.strip
      record.evaluation_llm_connector = identifier.blank? ? nil : resolve_test_suite_connector(identifier, tenant:)
    end

    def resolve_test_suite_agent(identifier, tenant:)
      value = identifier.to_s.strip
      return nil if value.blank?

      tenant.agents.find_by(id: value) || tenant.agents.find_by(slug: value) ||
        raise(ActiveRecord::RecordNotFound, "Agent '#{value}' was not found.")
    end

    def resolve_test_suite_mission(identifier, tenant:)
      value = identifier.to_s.strip
      return nil if value.blank?

      tenant.missions.find_by(id: value) || tenant.missions.find_by(slug: value) ||
        raise(ActiveRecord::RecordNotFound, "Mission '#{value}' was not found.")
    end

    def resolve_test_suite_connector(identifier, tenant:)
      tenant.connectors.find_by(id: identifier) ||
        raise(ActiveRecord::RecordNotFound, "Connector '#{identifier}' was not found.")
    end

    def tenant_test_suites(tenant)
      TestSuite.where(agent_id: tenant.agents.select(:id))
               .or(TestSuite.where(mission_id: tenant.missions.select(:id)))
               .includes(agent: :operation, mission: :operation)
    end
  end
end
