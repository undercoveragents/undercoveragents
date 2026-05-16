# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentAlpha::RuntimeContext do
  describe ".build" do
    let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
    let(:operation) { tenant.default_operation }
    let(:mission) { create(:mission, operation:) }
    let(:agent) { create(:agent, operation:, model_id: "gpt-4.1") }
    let(:skill) { create(:skill, skill_catalog:, name: "triage") }

    def channel_record
      @channel_record ||= create(:channel, :client, tenant:, name: "Preview Channel")
    end

    def client_record
      @client_record ||= create(:client, tenant:, agent:, default: true, name: "Preview Client")
    end

    def skill_catalog
      @skill_catalog ||= create(:skill_catalog, operation:, name: "Operations Skills")
    end

    def rag_flow
      @rag_flow ||= create(:rag_flow, operation:, name: "Incident Knowledge")
    end

    def connector_record
      @connector_record ||= create(:connector, :llm_provider, tenant:, name: "Platform LLM")
    end

    def test_suite
      @test_suite ||= create(:test_suite, agent:, name: "Operations Smoke")
    end

    def test_case
      @test_case ||= create(:test_case, test_suite:)
    end

    def test_suite_run
      @test_suite_run ||= create(:test_suite_run, test_suite:)
    end

    def tool_record
      @tool_record ||= begin
        connector = create(:connector, :sql_database, tenant:)
        create(
          :tool,
          :enabled,
          operation:,
          name: "Orders Explorer",
          toolable: Tools::SqlQuery.new(connector_id: connector.id, llm_config_source: "inherit"),
        )
      end
    end

    it "returns an empty runtime context when no ui context is present" do
      expect(described_class.build(ui_context: nil, tenant:)).to eq({})
    end

    it "preserves the verified ui context payload" do
      ui_context = {
        "page" => { "name" => "Dashboard" },
        "references" => [],
      }

      expect(described_class.build(ui_context:, tenant:)).to eq(ui_context:)
    end

    it "resolves the current mission by id within the tenant" do
      ui_context = {
        "current_object" => {
          "type" => "Mission",
          "class_name" => "Mission",
          "id" => mission.id,
          "slug" => mission.slug,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to include(ui_context:, mission:)
    end

    it "falls back to the mission slug when the page context omits the id" do
      ui_context = {
        "current_object" => {
          "type" => "Mission",
          "slug" => mission.slug,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to include(ui_context:, mission:)
    end

    it "leaves the ui context unchanged for unsupported current objects" do
      ui_context = {
        "current_object" => {
          "type" => "DashboardCard",
          "id" => mission.id,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to eq(ui_context:)
    end

    it "does not resolve records outside the current tenant" do
      foreign_tenant = create(:tenant).tap(&:ensure_core_resources!)
      foreign_mission = create(:mission, operation: foreign_tenant.default_operation)
      ui_context = {
        "current_object" => {
          "type" => "Mission",
          "class_name" => "Mission",
          "id" => foreign_mission.id,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to eq(ui_context:)
    end

    it "resolves the current agent by id within the tenant" do
      ui_context = {
        "current_object" => {
          "type" => "Agent",
          "class_name" => "Agent",
          "id" => agent.id,
          "slug" => agent.slug,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to include(ui_context:, current_agent: agent)
    end

    it "resolves the current client by id within the tenant" do
      ui_context = {
        "current_object" => {
          "type" => "Client",
          "class_name" => "Client",
          "id" => client_record.id,
          "slug" => client_record.slug,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to include(ui_context:, current_client: client_record)
    end

    it "resolves the current channel by id within the tenant" do
      ui_context = {
        "current_object" => {
          "type" => "Channel",
          "class_name" => "Channel",
          "id" => channel_record.id,
          "slug" => channel_record.slug,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to include(ui_context:, current_channel: channel_record)
    end

    it "resolves the current tool by id within the tenant" do
      ui_context = {
        "current_object" => {
          "type" => "Tool",
          "class_name" => "Tool",
          "id" => tool_record.id,
          "slug" => tool_record.slug,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to include(ui_context:, current_tool: tool_record)
    end

    it "resolves the current skill catalog by id within the tenant" do
      ui_context = {
        "current_object" => {
          "type" => "Skill catalog",
          "class_name" => "SkillCatalog",
          "id" => skill_catalog.id,
          "slug" => skill_catalog.slug,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to include(ui_context:, current_skill_catalog: skill_catalog)
    end

    it "resolves the current skill by id within the tenant" do
      ui_context = {
        "current_object" => {
          "type" => "Skill",
          "class_name" => "Skill",
          "id" => skill.id,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to include(ui_context:, current_skill: skill)
    end

    it "resolves the current RAG flow by id within the tenant" do
      ui_context = {
        "current_object" => {
          "type" => "Rag flow",
          "class_name" => "RagFlow",
          "id" => rag_flow.id,
          "slug" => rag_flow.slug,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to include(ui_context:, current_rag_flow: rag_flow)
    end

    it "resolves the current connector by id within the tenant" do
      ui_context = {
        "current_object" => {
          "type" => "Connector",
          "class_name" => "Connector",
          "id" => connector_record.id,
          "slug" => connector_record.slug,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to include(ui_context:, current_connector: connector_record)
    end

    it "resolves the current test suite by id within the tenant" do
      ui_context = {
        "current_object" => {
          "type" => "Test suite",
          "class_name" => "TestSuite",
          "id" => test_suite.id,
          "slug" => test_suite.slug,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to include(ui_context:, current_test_suite: test_suite)
    end

    it "resolves the current test suite from the current test case" do
      ui_context = {
        "current_object" => {
          "type" => "TestCase",
          "class_name" => "TestCase",
          "id" => test_case.id,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to include(ui_context:, current_test_suite: test_suite)
    end

    it "resolves the current test suite from the current test suite run" do
      ui_context = {
        "current_object" => {
          "type" => "TestSuiteRun",
          "class_name" => "TestSuiteRun",
          "id" => test_suite_run.id,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to include(ui_context:, current_test_suite: test_suite)
    end

    it "does not resolve a current test suite from a foreign nested test case" do
      foreign_tenant = create(:tenant).tap(&:ensure_core_resources!)
      foreign_suite = create(:test_suite, agent: create(:agent, operation: foreign_tenant.default_operation))
      foreign_test_case = create(:test_case, test_suite: foreign_suite)
      ui_context = {
        "current_object" => {
          "type" => "TestCase",
          "class_name" => "TestCase",
          "id" => foreign_test_case.id,
        },
      }

      expect(described_class.build(ui_context:, tenant:)).to eq(ui_context:)
    end

    it "skips mission resolution when no tenant is available" do
      ui_context = {
        "current_object" => {
          "type" => "Mission",
          "class_name" => "Mission",
          "id" => mission.id,
        },
      }

      expect(described_class.build(ui_context:, tenant: nil)).to eq(ui_context:)
    end

    it "skips agent resolution when no tenant is available" do
      ui_context = {
        "current_object" => {
          "type" => "Agent",
          "class_name" => "Agent",
          "id" => agent.id,
        },
      }

      expect(described_class.build(ui_context:, tenant: nil)).to eq(ui_context:)
    end

    it "skips client resolution when no tenant is available" do
      ui_context = {
        "current_object" => {
          "type" => "Client",
          "class_name" => "Client",
          "id" => client_record.id,
        },
      }

      expect(described_class.build(ui_context:, tenant: nil)).to eq(ui_context:)
    end

    it "skips tool resolution when no tenant is available" do
      ui_context = {
        "current_object" => {
          "type" => "Tool",
          "class_name" => "Tool",
          "id" => tool_record.id,
        },
      }

      expect(described_class.build(ui_context:, tenant: nil)).to eq(ui_context:)
    end

    it "skips channel resolution when no tenant is available" do
      ui_context = {
        "current_object" => {
          "type" => "Channel",
          "class_name" => "Channel",
          "id" => channel_record.id,
        },
      }

      expect(described_class.build(ui_context:, tenant: nil)).to eq(ui_context:)
    end

    it "skips skill catalog resolution when no tenant is available" do
      ui_context = {
        "current_object" => {
          "type" => "Skill catalog",
          "class_name" => "SkillCatalog",
          "id" => skill_catalog.id,
        },
      }

      expect(described_class.build(ui_context:, tenant: nil)).to eq(ui_context:)
    end

    it "skips connector resolution when no tenant is available" do
      ui_context = {
        "current_object" => {
          "type" => "Connector",
          "class_name" => "Connector",
          "id" => connector_record.id,
        },
      }

      expect(described_class.build(ui_context:, tenant: nil)).to eq(ui_context:)
    end

    it "skips test suite resolution when no tenant is available" do
      ui_context = {
        "current_object" => {
          "type" => "Test suite",
          "class_name" => "TestSuite",
          "id" => test_suite.id,
        },
      }

      expect(described_class.build(ui_context:, tenant: nil)).to eq(ui_context:)
    end
  end
end
