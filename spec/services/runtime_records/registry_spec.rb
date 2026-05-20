# frozen_string_literal: true

require "rails_helper"

RSpec.describe RuntimeRecords::Registry do
  include ChannelPluginSpecHelpers

  let(:tenant) { create(:tenant) }
  let(:operation) { create(:operation, tenant:) }
  let(:context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: nil,
      user: nil,
      tenant:,
      operation:,
    )
  end

  before do
    described_class.definitions.clear
  end

  describe ".fetch" do
    it "returns the registered mission definition" do
      definition = described_class.fetch("mission")

      expect(definition.label).to eq("Mission")
      expect(definition.default_page).to eq("designer")
    end

    it "returns the registered agent definition" do
      definition = described_class.fetch("agent")

      expect(definition.label).to eq("Agent")
      expect(definition.default_page).to eq("show")
    end

    it "returns the registered skill catalog definition" do
      definition = described_class.fetch("skill_catalog")

      expect(definition.label).to eq("Skill Catalog")
      expect(definition.default_page).to eq("show")
    end

    it "returns the registered test suite definition" do
      definition = described_class.fetch("test_suite")

      expect(definition.label).to eq("Test Suite")
      expect(definition.default_page).to eq("show")
    end

    it "returns the registered channel definition" do
      definition = described_class.fetch("channel")
      client_channel = create(:channel, :client, tenant:, name: "Preview Channel")
      api_channel = create(:channel, :api, tenant:, name: "API Channel")

      expect(definition.label).to eq("Channel")
      expect(definition.default_page_for(record: client_channel, context:)).to eq("preview")
      expect(definition.default_page_for(record: api_channel, context:)).to eq("show")
    end

    it "returns the registered tool definition" do
      definition = described_class.fetch("tool")

      expect(definition.label).to eq("Tool")
      expect(definition.default_page).to eq("show")
    end

    it "raises for unknown resources" do
      expect { described_class.fetch("unknown") }.to raise_error(KeyError, "Unknown resource 'unknown'.")
    end

    it "looks up definitions by their runtime label" do
      expect(described_class.definition_for_label("Skill Catalog")&.key).to eq("skill_catalog")
      expect(described_class.definition_for_label("Missing Label")).to be_nil
    end
  end

  describe "mission definition" do
    let(:definition) { described_class.fetch("mission") }

    it "normalizes static base attributes" do
      custom_definition = described_class::Definition.new(
        key: "custom",
        label: "Custom",
        model_class: Mission,
        permitted_attributes: [],
        scope_resolver: ->(_context) { Mission.none },
        base_attributes: { operation_id: operation.id },
        default_page: "index",
        page_resolver: ->(_page, record:, context:) { [record, context].compact.join(":") },
      )

      expect(custom_definition.base_attributes_for(context)).to eq({ "operation_id" => operation.id })
    end

    it "scopes missions to the current tenant and operation" do
      visible = create(:mission, operation:)
      hidden_operation = create(:mission, operation: create(:operation, tenant:))
      other_tenant = create(:tenant)
      hidden_tenant = create(:mission, operation: create(:operation, tenant: other_tenant))

      expect(definition.scope_for(context)).to contain_exactly(visible)
      expect(definition.scope_for(context)).not_to include(hidden_operation, hidden_tenant)
    end

    it "scopes missions by operation when no tenant is present" do
      visible = create(:mission, operation:)
      hidden_operation = create(:mission, operation: create(:operation, tenant:))

      expect(definition.scope_for(context.with(tenant: nil))).to contain_exactly(visible)
      expect(definition.scope_for(context.with(tenant: nil))).not_to include(hidden_operation)
    end

    it "raises when the operation falls outside the active tenant" do
      foreign_context = context.with(operation: create(:operation, tenant: create(:tenant)))

      expect { definition.base_attributes_for(foreign_context) }
        .to raise_error(ArgumentError, "The current operation is outside the active tenant.")
    end

    it "raises when no current operation is available" do
      expect { definition.base_attributes_for(context.with(operation: nil)) }
        .to raise_error(ArgumentError, "No current operation is available for missions.")
    end

    it "returns collection and record paths for supported pages", :aggregate_failures do
      mission = create(:mission, operation:)

      helpers = Rails.application.routes.url_helpers

      expect(definition.path_for("index", record: nil, context:)).to eq(helpers.admin_missions_path)
      expect(definition.path_for("new", record: nil, context:)).to eq(helpers.new_admin_mission_path)
      expect(definition.path_for("edit", record: mission, context:)).to eq(helpers.edit_admin_mission_path(mission))
      expect(definition.path_for("designer", record: mission, context:)).to eq(
        helpers.designer_admin_mission_path(mission),
      )
    end

    it "requires a record for edit and designer pages" do
      expect { definition.path_for("edit", record: nil, context:) }
        .to raise_error(ArgumentError, "Mission page 'edit' requires a record.")
      expect { definition.path_for("designer", record: nil, context:) }
        .to raise_error(ArgumentError, "Mission page 'designer' requires a record.")
    end

    it "raises for unknown mission pages" do
      mission = create(:mission, operation:)

      expect { definition.path_for("show", record: mission, context:) }
        .to raise_error(ArgumentError, "Unknown page 'show' for mission. Use index, new, edit, or designer.")
    end
  end

  describe "agent definition" do
    let(:definition) { described_class.fetch("agent") }

    it "scopes agents to the current tenant and operation" do
      visible = create(:agent, operation:)
      hidden_operation = create(:agent, operation: create(:operation, tenant:))
      hidden_tenant = create(:agent, operation: create(:operation, tenant: create(:tenant)))

      expect(definition.scope_for(context)).to contain_exactly(visible)
      expect(definition.scope_for(context)).not_to include(hidden_operation, hidden_tenant)
    end

    it "scopes agents by operation when no tenant is present" do
      visible = create(:agent, operation:)
      hidden_operation = create(:agent, operation: create(:operation, tenant:))

      expect(definition.scope_for(context.with(tenant: nil))).to contain_exactly(visible)
      expect(definition.scope_for(context.with(tenant: nil))).not_to include(hidden_operation)
    end

    it "raises when the agent operation falls outside the active tenant" do
      foreign_context = context.with(operation: create(:operation, tenant: create(:tenant)))

      expect { definition.base_attributes_for(foreign_context) }
        .to raise_error(ArgumentError, "The current operation is outside the active tenant.")
    end

    it "raises when no current operation is available for agents" do
      expect { definition.base_attributes_for(context.with(operation: nil)) }
        .to raise_error(ArgumentError, "No current operation is available for agents.")
    end

    it "returns collection and record paths for supported pages", :aggregate_failures do
      agent = create(:agent, operation:)
      helpers = Rails.application.routes.url_helpers

      expect(definition.path_for("index", record: nil, context:)).to eq(helpers.admin_agents_path)
      expect(definition.path_for("new", record: nil, context:)).to eq(helpers.new_admin_agent_path)
      expect(definition.path_for("show", record: agent, context:)).to eq(helpers.admin_agent_path(agent))
      expect(definition.path_for("edit", record: agent, context:)).to eq(helpers.edit_admin_agent_path(agent))
    end

    it "requires a record for show and edit pages" do
      expect { definition.path_for("show", record: nil, context:) }
        .to raise_error(ArgumentError, "Agent page 'show' requires a record.")
      expect { definition.path_for("edit", record: nil, context:) }
        .to raise_error(ArgumentError, "Agent page 'edit' requires a record.")
    end

    it "raises for unknown agent pages" do
      agent = create(:agent, operation:)

      expect { definition.path_for("designer", record: agent, context:) }
        .to raise_error(ArgumentError, "Unknown page 'designer' for agent. Use index, new, show, or edit.")
    end
  end

  describe "automation trigger definition" do
    let(:definition) { described_class.fetch("automation_trigger") }
    let(:admin_user) { create(:user, :admin, tenant:) }
    let(:manager) { RuntimeRecords::Manager.new(context.with(user: admin_user)) }
    let(:mission) { create(:mission, operation:) }
    let(:rag_flow) { create(:rag_flow, operation:) }

    it "scopes automation triggers to the current tenant and operation" do
      visible = create(:automation_trigger, target: mission)
      hidden_operation = create(:automation_trigger, target: create(:mission, operation: create(:operation, tenant:)))
      hidden_tenant = create(:automation_trigger,
                             target: create(:mission, operation: create(:operation, tenant: create(:tenant))),)

      expect(definition.scope_for(context)).to contain_exactly(visible)
      expect(definition.scope_for(context)).not_to include(hidden_operation, hidden_tenant)
    end

    it "scopes automation triggers by operation when no tenant context is present" do
      visible = create(:automation_trigger, target: mission)
      hidden_operation = create(:automation_trigger, target: create(:mission, operation: create(:operation, tenant:)))

      expect(definition.scope_for(context.with(tenant: nil))).to contain_exactly(visible)
      expect(definition.scope_for(context.with(tenant: nil))).not_to include(hidden_operation)
    end

    it "resolves target from context.mission field and uses its operation" do
      create(:automation_trigger, target: mission)

      result = definition.scope_for(context.with(mission:))

      expect(result).to be_a(ActiveRecord::Relation)
    end

    it "returns mission paths for index, new, and edit" do
      trigger = create(:automation_trigger, target: mission)
      mission_context = context.with(
        ui_context: { "current_object" => { "class_name" => "Mission", "id" => mission.id } },
      )
      trigger_context = context.with(
        ui_context: { "current_object" => { "class_name" => "AutomationTrigger", "id" => trigger.id } },
      )
      helpers = Rails.application.routes.url_helpers

      expect(definition.path_for("index", record: nil, context: mission_context))
        .to eq(helpers.admin_mission_automation_triggers_path(mission))
      expect(definition.path_for("new", record: nil, context: mission_context))
        .to eq(helpers.new_admin_mission_automation_trigger_path(mission))
      expect(definition.path_for("index", record: nil, context: trigger_context))
        .to eq(helpers.admin_mission_automation_triggers_path(mission))
      expect(definition.path_for("edit", record: trigger, context:))
        .to eq(helpers.edit_admin_mission_automation_trigger_path(mission, trigger))
      expect(definition.path_for("index", record: trigger, context:))
        .to eq(helpers.admin_mission_automation_triggers_path(mission))
    end

    it "returns rag-flow paths for index, new, and edit" do
      rag_trigger = create(:automation_trigger, target: rag_flow)
      rag_flow_context = context.with(
        ui_context: { "current_object" => { "class_name" => "RagFlow", "id" => rag_flow.id } },
      )
      helpers = Rails.application.routes.url_helpers

      expect(definition.path_for("index", record: nil, context: rag_flow_context))
        .to eq(helpers.admin_rag_flow_automation_triggers_path(rag_flow))
      expect(definition.path_for("new", record: nil, context: rag_flow_context))
        .to eq(helpers.new_admin_rag_flow_automation_trigger_path(rag_flow))
      expect(definition.path_for("edit", record: rag_trigger, context:))
        .to eq(helpers.edit_admin_rag_flow_automation_trigger_path(rag_flow, rag_trigger))
    end

    it "raises for missing or invalid context", :aggregate_failures do
      expect { definition.base_attributes_for(context.with(operation: nil)) }
        .to raise_error(ArgumentError, "No current operation is available for automation triggers.")

      expect { definition.path_for("index", record: nil, context:) }
        .to raise_error(ArgumentError, "Automation trigger page 'index' requires a mission or RAG flow context.")

      expect { definition.path_for("show", record: nil, context:) }
        .to raise_error(ArgumentError, "Unknown page 'show' for automation_trigger. Use index, new, or edit.")

      expect { definition.path_for("edit", record: nil, context:) }
        .to raise_error(ArgumentError, "Automation trigger page 'edit' requires a record.")
    end

    it "raises for unsupported schedulable types", :aggregate_failures do
      unsupported_trigger = create(:automation_trigger, target: mission)
      allow(unsupported_trigger).to receive(:schedulable).and_return(operation)

      expect { definition.path_for("edit", record: unsupported_trigger, context:) }
        .to raise_error(ArgumentError, /Unsupported automation target/)
      expect { definition.path_for("index", record: unsupported_trigger, context:) }
        .to raise_error(ArgumentError, /Unsupported automation target/)
    end

    it "raises when context identifier is blank or unrecognized", :aggregate_failures do
      blank_id_context = context.with(
        ui_context: { "current_object" => { "class_name" => "Mission", "id" => nil } },
      )
      expect { definition.path_for("index", record: nil, context: blank_id_context) }
        .to raise_error(ArgumentError, "Automation trigger page 'index' requires a mission or RAG flow context.")

      unknown_context = context.with(
        ui_context: { "current_object" => { "class_name" => "Agent", "id" => "1" } },
      )
      expect { definition.path_for("index", record: nil, context: unknown_context) }
        .to raise_error(ArgumentError, "Automation trigger page 'index' requires a mission or RAG flow context.")

      nonexistent_trigger_context = context.with(
        ui_context: { "current_object" => { "class_name" => "AutomationTrigger", "id" => 0 } },
      )
      expect { definition.path_for("index", record: nil, context: nonexistent_trigger_context) }
        .to raise_error(ArgumentError, "Automation trigger page 'index' requires a mission or RAG flow context.")
    end

    it "raises for invalid or missing target on create", :aggregate_failures do
      expect do
        manager.create(
          resource: "automation_trigger",
          attributes: { name: "Bad", trigger_type: "schedule", target_type: "channel", target_id: 1 },
        )
      end.to raise_error(ArgumentError, "Unsupported automation target 'channel'.")

      expect do
        manager.create(resource: "automation_trigger", attributes: { name: "Missing", trigger_type: "schedule" })
      end.to raise_error(
        ArgumentError,
        "Provide target_type and target_id, or run this from a mission or RAG flow page.",
      )

      expect do
        manager.create(
          resource: "automation_trigger",
          attributes: { name: "Missing", trigger_type: "schedule", target_type: "mission", target_id: "missing" },
        )
      end.to raise_error(ActiveRecord::RecordNotFound, "Mission 'missing' was not found.")
    end

    it "creates automation triggers for mission and rag-flow targets" do
      mission_context = context.with(
        user: admin_user,
        ui_context: { "current_object" => { "class_name" => "Mission", "id" => mission.id } },
      )

      mission_result = RuntimeRecords::Manager.new(mission_context).create(
        resource: "automation_trigger",
        attributes: {
          name: "Mission Schedule",
          trigger_type: "schedule",
          cron_expression: "0 * * * *",
          timezone: "UTC",
        },
      )
      rag_result = manager.create(
        resource: "automation_trigger",
        attributes: {
          name: "RAG Webhook",
          trigger_type: "webhook",
          target_type: "rag_flow",
          target_id: rag_flow.id,
        },
      )

      expect(mission_result.record.schedulable).to eq(mission)
      expect(rag_result.record.schedulable).to eq(rag_flow)
    end

    it "updates an automation trigger name without changing target" do
      rag_trigger = create(:automation_trigger, target: rag_flow)
      mission_trigger = create(:automation_trigger, target: mission)

      updated_rag = manager.update(
        resource: "automation_trigger",
        record_id: rag_trigger.id,
        attributes: { name: "RAG Webhook Updated", target_type: "rag_flow", target_id: rag_flow.id },
      )
      updated_mission = manager.update(
        resource: "automation_trigger",
        record_id: mission_trigger.id,
        attributes: { name: "Mission Schedule Renamed" },
      )

      expect(updated_rag.record.reload.name).to eq("RAG Webhook Updated")
      expect(updated_mission.record.reload.name).to eq("Mission Schedule Renamed")
    end

    it "raises when trying to change an automation trigger's target" do
      rag_trigger = create(:automation_trigger, target: rag_flow)

      expect do
        manager.update(
          resource: "automation_trigger",
          record_id: rag_trigger.id,
          attributes: { target_type: "mission", target_id: mission.id },
        )
      end.to raise_error(ArgumentError, "Automation trigger target cannot be changed once the trigger exists.")
    end
  end

  describe "skill catalog definition" do
    let(:definition) { described_class.fetch("skill_catalog") }

    it "scopes skill catalogs to the current tenant and operation" do
      visible = create(:skill_catalog, operation:)
      hidden_operation = create(:skill_catalog, operation: create(:operation, tenant:))
      hidden_tenant = create(:skill_catalog, operation: create(:operation, tenant: create(:tenant)))

      expect(definition.scope_for(context)).to contain_exactly(visible)
      expect(definition.scope_for(context)).not_to include(hidden_operation, hidden_tenant)
    end

    it "scopes skill catalogs by operation when no tenant is present" do
      visible = create(:skill_catalog, operation:)
      hidden_operation = create(:skill_catalog, operation: create(:operation, tenant:))

      expect(definition.scope_for(context.with(tenant: nil))).to contain_exactly(visible)
      expect(definition.scope_for(context.with(tenant: nil))).not_to include(hidden_operation)
    end

    it "normalizes skill catalog base attributes" do
      expect(definition.base_attributes_for(context)).to eq({ "operation" => operation })
    end

    it "raises when the skill catalog operation falls outside the active tenant" do
      foreign_context = context.with(operation: create(:operation, tenant: create(:tenant)))

      expect { definition.base_attributes_for(foreign_context) }
        .to raise_error(ArgumentError, "The current operation is outside the active tenant.")
    end

    it "raises when no current operation is available for skill catalogs" do
      expect { definition.base_attributes_for(context.with(operation: nil)) }
        .to raise_error(ArgumentError, "No current operation is available for skill catalogs.")
    end

    it "returns collection and record paths for supported pages", :aggregate_failures do
      skill_catalog = create(:skill_catalog, operation:)
      helpers = Rails.application.routes.url_helpers

      expect(definition.path_for("index", record: nil, context:)).to eq(helpers.admin_skill_catalogs_path)
      expect(definition.path_for("new", record: nil, context:)).to eq(helpers.new_admin_skill_catalog_path)
      expect(definition.path_for("show", record: skill_catalog, context:)).to eq(
        helpers.admin_skill_catalog_path(skill_catalog),
      )
      expect(definition.path_for("edit", record: skill_catalog, context:)).to eq(
        helpers.edit_admin_skill_catalog_path(skill_catalog),
      )
    end

    it "requires a record for show and edit pages" do
      expect { definition.path_for("show", record: nil, context:) }
        .to raise_error(ArgumentError, "Skill catalog page 'show' requires a record.")
      expect { definition.path_for("edit", record: nil, context:) }
        .to raise_error(ArgumentError, "Skill catalog page 'edit' requires a record.")
    end

    it "raises for unknown skill catalog pages" do
      skill_catalog = create(:skill_catalog, operation:)

      expect { definition.path_for("designer", record: skill_catalog, context:) }
        .to raise_error(ArgumentError, "Unknown page 'designer' for skill catalog. Use index, new, show, or edit.")
    end
  end

  describe "test suite definition" do
    let(:definition) { described_class.fetch("test_suite") }

    it "scopes test suites to the current tenant" do
      visible = create(:test_suite, agent: create(:agent, operation:))
      hidden = create(:test_suite, agent: create(:agent, operation: create(:operation, tenant: create(:tenant))))

      expect(definition.scope_for(context)).to contain_exactly(visible)
      expect(definition.scope_for(context)).not_to include(hidden)
    end

    it "returns collection and record paths for supported pages", :aggregate_failures do
      test_suite = create(:test_suite, agent: create(:agent, operation:))
      helpers = Rails.application.routes.url_helpers

      expect(definition.path_for("index", record: nil, context:)).to eq(helpers.admin_test_suites_path)
      expect(definition.path_for("new", record: nil, context:)).to eq(helpers.new_admin_test_suite_path)
      expect(definition.path_for("show", record: test_suite, context:)).to eq(helpers.admin_test_suite_path(test_suite))
      expect(definition.path_for("edit", record: test_suite, context:)).to eq(
        helpers.edit_admin_test_suite_path(test_suite),
      )
    end

    it "requires a record for show and edit pages" do
      expect { definition.path_for("show", record: nil, context:) }
        .to raise_error(ArgumentError, "Test suite page 'show' requires a record.")
      expect { definition.path_for("edit", record: nil, context:) }
        .to raise_error(ArgumentError, "Test suite page 'edit' requires a record.")
    end

    it "raises for unknown test suite pages" do
      test_suite = create(:test_suite, agent: create(:agent, operation:))

      expect { definition.path_for("designer", record: test_suite, context:) }
        .to raise_error(ArgumentError, "Unknown page 'designer' for test_suite. Use index, new, show, or edit.")
    end

    it "derives the active tenant for test suites from context or operation", :aggregate_failures do
      expect(described_class.send(:test_suite_tenant, context)).to eq(tenant)
      expect(described_class.send(:test_suite_tenant, context.with(tenant: nil))).to eq(tenant)

      expect { described_class.send(:test_suite_tenant, context.with(tenant: nil, operation: nil)) }
        .to raise_error(ArgumentError, "No active tenant is available for test suites.")
    end

    it "assigns test suite targets for agent and mission suites", :aggregate_failures do
      agent = create(:agent, operation:)
      mission = create(:mission, operation:)
      connector = create(:connector, :llm_provider, tenant:)

      agent_suite = build(:test_suite, agent:, evaluation_llm_connector: connector, evaluation_model_id: "gpt-4.1-mini")
      described_class.send(:assign_test_suite_target!, agent_suite, { "agent_id" => agent.id }, tenant:)
      expect(agent_suite.suite_type).to eq("agent")
      expect(agent_suite.agent).to eq(agent)
      expect(agent_suite.mission).to be_nil

      mission_suite = build(
        :test_suite,
        agent:,
        evaluation_llm_connector: connector,
        evaluation_model_id: "gpt-4.1-mini",
      )
      described_class.send(:assign_test_suite_target!, mission_suite, { "mission_id" => mission.id }, tenant:)
      expect(mission_suite.suite_type).to eq("mission")
      expect(mission_suite.mission).to eq(mission)
      expect(mission_suite.agent).to be_nil
      expect(mission_suite.evaluation_llm_connector).to be_nil
      expect(mission_suite.evaluation_model_id).to be_nil
    end

    it "raises for invalid or incomplete test suite target attributes", :aggregate_failures do
      unassigned_suite = TestSuite.new

      expect do
        described_class.send(:assign_test_suite_target!, unassigned_suite, { "suite_type" => "agent" }, tenant:)
      end.to raise_error(ArgumentError, "Agent test suites require agent_id.")

      expect do
        described_class.send(:assign_test_suite_target!, build(:test_suite), { "suite_type" => "mission" }, tenant:)
      end.to raise_error(ArgumentError, "Mission test suites require mission_id.")

      expect do
        described_class.send(:assign_test_suite_target!, build(:test_suite), { "suite_type" => "other" }, tenant:)
      end.to raise_error(ArgumentError, "Unknown suite_type 'other'. Use agent or mission.")
    end

    it "assigns evaluation connectors for agent test suites", :aggregate_failures do
      agent = create(:agent, operation:)
      connector = create(:connector, :llm_provider, tenant:)

      suite = build(:test_suite, agent:, evaluation_llm_connector: connector)
      described_class.send(:assign_test_suite_connector!, suite, {}, tenant:)
      expect(suite.evaluation_llm_connector).to eq(connector)

      described_class.send(:assign_test_suite_connector!, suite, { "evaluation_llm_connector_id" => "   " }, tenant:)
      expect(suite.evaluation_llm_connector).to be_nil

      described_class.send(
        :assign_test_suite_connector!,
        suite,
        { "evaluation_llm_connector_id" => connector.id },
        tenant:,
      )
      expect(suite.evaluation_llm_connector).to eq(connector)
    end

    it "leaves mission test suite connectors unchanged" do
      connector = create(:connector, :llm_provider, tenant:)
      mission = create(:mission, operation:)
      mission_suite = build(:test_suite, :mission_suite, mission:, evaluation_llm_connector: connector)
      described_class.send(
        :assign_test_suite_connector!,
        mission_suite,
        { "evaluation_llm_connector_id" => "missing" },
        tenant:,
      )
      expect(mission_suite.evaluation_llm_connector).to eq(connector)
    end

    it "resolves mission and connector identifiers for test suites", :aggregate_failures do
      connector = create(:connector, :llm_provider, tenant:)
      mission = create(:mission, operation:)

      expect(described_class.send(:resolve_test_suite_mission, " ", tenant:)).to be_nil
      expect(described_class.send(:resolve_test_suite_mission, mission.id, tenant:)).to eq(mission)
      expect(described_class.send(:resolve_test_suite_connector, connector.id, tenant:)).to eq(connector)

      expect { described_class.send(:resolve_test_suite_mission, "missing", tenant:) }
        .to raise_error(ActiveRecord::RecordNotFound, "Mission 'missing' was not found.")
      expect { described_class.send(:resolve_test_suite_connector, "missing", tenant:) }
        .to raise_error(ActiveRecord::RecordNotFound, "Connector 'missing' was not found.")
    end
  end

  describe "tool definition" do
    let(:definition) { described_class.fetch("tool") }

    it "scopes tools to the current tenant and operation" do
      connector = create(:connector, :mcp_server, tenant:)
      visible = create(
        :tool,
        operation:,
        name: "Visible Tool",
        toolable: Tools::McpServer.new(connector_id: connector.id),
      )
      hidden_operation = create(
        :tool,
        operation: create(:operation, tenant:),
        name: "Hidden Tool",
        toolable: Tools::McpServer.new(connector_id: connector.id),
      )

      expect(definition.scope_for(context)).to contain_exactly(visible)
      expect(definition.scope_for(context)).not_to include(hidden_operation)
    end

    it "scopes tools by operation when no tenant is present" do
      connector = create(:connector, :mcp_server, tenant:)
      visible = create(
        :tool,
        operation:,
        name: "Visible Tool",
        toolable: Tools::McpServer.new(connector_id: connector.id),
      )
      hidden_operation = create(
        :tool,
        operation: create(:operation, tenant:),
        name: "Hidden Tool",
        toolable: Tools::McpServer.new(connector_id: connector.id),
      )

      expect(definition.scope_for(context.with(tenant: nil))).to contain_exactly(visible)
      expect(definition.scope_for(context.with(tenant: nil))).not_to include(hidden_operation)
    end

    it "normalizes tool base attributes" do
      expect(definition.base_attributes_for(context)).to eq({ "operation" => operation })
    end

    it "raises when the tool operation falls outside the active tenant" do
      foreign_context = context.with(operation: create(:operation, tenant: create(:tenant)))

      expect { definition.base_attributes_for(foreign_context) }
        .to raise_error(ArgumentError, "The current operation is outside the active tenant.")
    end

    it "raises when no current operation is available for tools" do
      expect { definition.base_attributes_for(context.with(operation: nil)) }
        .to raise_error(ArgumentError, "No current operation is available for tools.")
    end

    it "returns collection and record paths for supported pages", :aggregate_failures do
      connector = create(:connector, :mcp_server, tenant:)
      tool_record = create(
        :tool,
        operation:,
        name: "Filesystem MCP",
        toolable: Tools::McpServer.new(connector_id: connector.id),
      )
      helpers = Rails.application.routes.url_helpers

      expect(definition.path_for("index", record: nil, context:)).to eq(helpers.admin_tools_path)
      expect(definition.path_for("new", record: nil, context:)).to eq(helpers.new_admin_tool_path)
      expect(definition.path_for("show", record: tool_record, context:)).to eq(helpers.admin_tool_path(tool_record))
      expect(definition.path_for("edit", record: tool_record, context:))
        .to eq(helpers.edit_admin_tool_path(tool_record))
    end

    it "requires a record for show and edit pages" do
      expect { definition.path_for("show", record: nil, context:) }
        .to raise_error(ArgumentError, "Tool page 'show' requires a record.")
      expect { definition.path_for("edit", record: nil, context:) }
        .to raise_error(ArgumentError, "Tool page 'edit' requires a record.")
    end

    it "raises for unknown tool pages" do
      connector = create(:connector, :mcp_server, tenant:)
      tool_record = create(
        :tool,
        operation:,
        name: "Filesystem MCP",
        toolable: Tools::McpServer.new(connector_id: connector.id),
      )

      expect { definition.path_for("designer", record: tool_record, context:) }
        .to raise_error(ArgumentError, "Unknown page 'designer' for tool. Use index, new, show, or edit.")
    end

    it "prevents changing the tool type during update" do
      connector = create(:connector, :mcp_server, tenant:)
      tool_record = create(
        :tool,
        operation:,
        name: "Filesystem MCP",
        toolable: Tools::McpServer.new(connector_id: connector.id),
      )

      expect do
        definition.update_handler.call(record: tool_record, attributes: { "tool_type" => "sql_query" })
      end.to raise_error(ArgumentError, "Tool type cannot be changed once the tool exists.")
    end
  end

  describe "channel definition" do
    let(:definition) { described_class.fetch("channel") }

    it "scopes channels to the current operation" do
      visible = create(:channel, :client, tenant:, operation:)
      hidden = create(:channel, :client, tenant:, operation: create(:operation, tenant:))

      expect(definition.scope_for(context)).to contain_exactly(visible)
      expect(definition.scope_for(context)).not_to include(hidden)
    end

    it "uses the active operation as the base attribute" do
      expect(definition.base_attributes_for(context)).to eq({ "operation" => operation, "tenant" => tenant })
    end

    it "falls back to the show page when no record is provided" do
      expect(definition.default_page_for(record: nil, context:)).to eq("show")
    end

    it "raises when no active operation is available for channels" do
      expect { definition.base_attributes_for(context.with(operation: nil)) }
        .to raise_error(ArgumentError, "No active operation is available for channels.")
    end

    it "returns collection and record paths for supported pages", :aggregate_failures do
      channel = create(:channel, :client, tenant:, operation:, name: "Support Portal")
      helpers = Rails.application.routes.url_helpers

      expect(definition.path_for("index", record: nil, context:)).to eq(helpers.admin_channels_path)
      expect(definition.path_for("new", record: nil, context:)).to eq(helpers.new_admin_channel_path)
      expect(definition.path_for("show", record: channel, context:)).to eq(helpers.admin_channel_path(channel))
      expect(definition.path_for("edit", record: channel, context:)).to eq(helpers.edit_admin_channel_path(channel))
      expect(definition.path_for("preview", record: channel, context:)).to eq(
        helpers.admin_channel_path(channel, view: :preview),
      )
    end

    it "requires a record for show, edit, and preview pages" do
      expect { definition.path_for("show", record: nil, context:) }
        .to raise_error(ArgumentError, "Channel page 'show' requires a record.")
      expect { definition.path_for("edit", record: nil, context:) }
        .to raise_error(ArgumentError, "Channel page 'edit' requires a record.")
      expect { definition.path_for("preview", record: nil, context:) }
        .to raise_error(ArgumentError, "Channel page 'preview' requires a record.")
    end

    it "rejects preview for non-client channels" do
      api_channel = create(:channel, :api, tenant:, operation:, name: "Public API")

      expect { definition.path_for("preview", record: api_channel, context:) }
        .to raise_error(ArgumentError, "Channel page 'preview' is only available for client channels.")
    end

    it "raises for unknown channel pages" do
      channel = create(:channel, :client, tenant:, operation:, name: "Support Portal")

      expect { definition.path_for("designer", record: channel, context:) }
        .to raise_error(ArgumentError, "Unknown page 'designer' for channel. Use index, new, show, edit, or preview.")
    end
  end

  describe "channel runtime helper internals" do
    let(:definition) { described_class.fetch("channel") }

    it "requires a channel type when creating channels" do
      expect do
        described_class.send(
          :channel_create,
          context:,
          definition:,
          attributes: { "name" => "Untyped" },
          authorize: ->(*) {},
        )
      end.to raise_error(ArgumentError, "Channel create requires channel_type.")
    end

    it "ignores unknown channel configuration setters" do
      channel = build(:channel, :client, name: "Before")

      described_class.send(:apply_channel_configuration!, channel, { "name" => "After", "unknown" => "ignored" })

      expect(channel.name).to eq("After")
    end

    it "ignores channel plugin types without declared attribute metadata" do
      stub_const("WithAttributes", Class.new)
      stub_const("WithoutAttributes", Class.new)
      with_attributes = class_double(WithAttributes, attribute_types: { "foo" => nil, "bar" => nil })
      without_attributes = class_double(WithoutAttributes)

      allow(ChannelPlugin).to receive(:type_keys).and_return(["with", "without"])
      allow(ChannelPlugin).to receive(:resolve).with("with").and_return(with_attributes)
      allow(ChannelPlugin).to receive(:resolve).with("without").and_return(without_attributes)

      expect(described_class.send(:channel_plugin_attribute_keys)).to eq(["foo", "bar"])
    end

    it "no-ops target sync for unsupported channel types" do
      channel = build(:channel, tenant:, operation:, channel_type: "webhook_relay")

      expect do
        described_class.send(:sync_channel_targets!, channel, attributes: {}, operation:, creating: false)
      end.not_to raise_error
    end

    it "keeps single-target mission channel targets untouched when no mission update is requested" do
      with_mission_only_channel_type do
        channel = create(:channel, tenant:, operation:, channel_type: "mission_only_spec")
        mission = create(:mission, operation:)
        target = create(:channel_target, :mission, channel:, target: mission, default: true)

        described_class.send(:sync_channel_targets!, channel, attributes: {}, operation:, creating: false)

        expect(channel.reload.channel_targets).to contain_exactly(target)
      end
    end

    it "keeps client targets untouched when no agent update is requested" do
      channel = create(:channel, :client, tenant:, operation:)
      agent = create(:agent, operation:)
      target = create(:channel_target, channel:, target: agent, default: true)

      described_class.send(:sync_client_channel_target!, channel, attributes: {}, operation:, creating: false)

      expect(channel.reload.channel_targets).to contain_exactly(target)
    end

    it "syncs client channel targets when an agent id is provided" do
      channel = create(:channel, :client, tenant:, operation:)
      agent = create(:agent, operation:)

      described_class.send(
        :sync_client_channel_target!,
        channel,
        attributes: { "agent_id" => agent.id },
        operation:,
        creating: false,
      )

      expect(channel.reload.default_target.target).to eq(agent)
    end

    it "syncs single-target mission channel targets when a mission id is provided" do
      with_mission_only_channel_type do
        channel = create(:channel, tenant:, operation:, channel_type: "mission_only_spec")
        mission = create(:mission, operation:)

        described_class.send(
          :sync_channel_targets!,
          channel,
          attributes: { "mission_id" => mission.id },
          operation:,
          creating: false,
        )

        expect(channel.reload.default_target.target).to eq(mission)
      end
    end

    it "keeps scoped API targets untouched when no sync-driving attributes are present" do
      channel = create(:channel, :api, tenant:, operation:, configuration: { "access_scope" => "scoped" })
      agent = create(:agent, operation:)
      target = create(:channel_target, channel:, target: agent, default: true)

      described_class.send(:sync_api_channel_targets!, channel, attributes: {}, operation:, creating: false)

      expect(channel.reload.channel_targets).to contain_exactly(target)
    end

    it "returns nil for blank channel agent identifiers" do
      expect(described_class.send(:resolve_channel_agent, "   ", operation:)).to be_nil
    end

    it "returns nil for unsupported single-target kinds" do
      channel = create(:channel, :api, tenant:, operation:)

      expect(
        described_class.send(
          :resolve_single_channel_target,
          channel,
          attributes: { "target_kind" => "unsupported" },
          operation:,
        ),
      ).to be_nil
    end

    it "does not create another API credential when one already exists" do
      channel = create(:channel, :api, tenant:, operation:)
      create(:channel_credential, channel:, name: "Primary token")

      expect do
        described_class.send(:ensure_api_channel_credential!, channel)
      end.not_to change(ChannelCredential, :count)
    end
  end
end
