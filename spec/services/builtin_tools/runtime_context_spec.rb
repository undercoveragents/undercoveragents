# frozen_string_literal: true

require "rails_helper"

RSpec.describe BuiltinTools::RuntimeContext do
  after do
    Current.reset
  end

  describe ".build" do
    let(:tenant) { create(:tenant) }
    let(:operation) { create(:operation, tenant:) }

    it "uses the parent chat user and mission operation when both are available" do
      user = create(:user, :admin, tenant:)
      mission = create(:mission, operation:)
      chat = create(:chat, :application_context, user:)

      context = described_class.build(parent_chat: chat, mission:)

      expect(context.user).to eq(user)
      expect(context.tenant).to eq(tenant)
      expect(context.operation).to eq(operation)
    end

    it "falls back to the mission tenant when there is no parent chat user" do
      mission = create(:mission, operation:)

      context = described_class.build(mission:)

      expect(context.user).to be_nil
      expect(context.tenant).to eq(tenant)
      expect(context.operation).to eq(operation)
    end

    it "resolves the operation from ui_context by id" do
      Current.tenant = tenant

      context = described_class.build(ui_context: { "operation" => { "id" => operation.id } })

      expect(context.operation).to eq(operation)
    end

    it "resolves the operation from ui_context by slug" do
      Current.tenant = tenant

      context = described_class.build(ui_context: { "operation" => { "slug" => operation.slug } })

      expect(context.operation).to eq(operation)
    end

    it "returns nil when ui_context does not contain an operation payload" do
      Current.tenant = tenant

      context = described_class.build(ui_context: { "page" => { "name" => "Dashboard" } })

      expect(context.operation).to be_nil
    end

    it "returns nil when no tenant can be resolved for ui_context navigation" do
      context = described_class.build(ui_context: { "operation" => { "id" => operation.id } })

      expect(context.tenant).to be_nil
      expect(context.operation).to be_nil
    end

    it "falls back to Current tenant and Current operation when no other context is available" do
      Current.tenant = tenant
      Current.operation = operation

      context = described_class.build

      expect(context.tenant).to eq(tenant)
      expect(context.operation).to eq(operation)
    end

    it "uses the agent tenant to resolve the ui_context operation when no user or mission is present" do
      tenant.ensure_core_resources!
      builtin_agent = create(:agent, operation: tenant.headquarter_operation)

      context = described_class.build(
        agent: builtin_agent,
        ui_context: { "operation" => { "id" => tenant.default_operation.id } },
      )

      expect(context.tenant).to eq(tenant)
      expect(context.operation).to eq(tenant.default_operation)
    end

    it "prefers the current page record operation over a mismatched ui_context operation" do
      tenant.ensure_core_resources!
      other_operation = tenant.headquarter_operation
      builtin_agent = build(:agent, operation: tenant.headquarter_operation)
      skill_catalog = create(:skill_catalog, operation:, name: "Operations Skills")

      context = described_class.build(
        agent: builtin_agent,
        ui_context: {
          "operation" => { "id" => other_operation.id },
          "current_object" => {
            "class_name" => "SkillCatalog",
            "type" => "Skill catalog",
            "id" => skill_catalog.id,
            "slug" => skill_catalog.slug,
          },
        },
      )

      expect(context.tenant).to eq(tenant)
      expect(context.operation).to eq(operation)
    end

    it "derives the operation from the current test suite record on tenant-scoped pages" do
      tenant.ensure_core_resources!
      agent = create(:agent, operation:)
      test_suite = create(:test_suite, agent:)

      context = described_class.build(
        ui_context: {
          "current_object" => {
            "class_name" => "TestSuite",
            "type" => "Test suite",
            "id" => test_suite.id,
            "slug" => test_suite.slug,
          },
        },
        agent: build(:agent, operation: tenant.headquarter_operation),
      )

      expect(context.tenant).to eq(tenant)
      expect(context.operation).to eq(operation)
    end

    it "derives the operation from the current skill record when only the type is present" do
      tenant.ensure_core_resources!
      skill_catalog = create(:skill_catalog, operation:)
      skill = create(:skill, skill_catalog:)

      context = described_class.build(
        ui_context: {
          "current_object" => {
            "type" => "Skill",
            "id" => skill.id,
          },
        },
        agent: build(:agent, operation: tenant.headquarter_operation),
      )

      expect(context.tenant).to eq(tenant)
      expect(context.operation).to eq(operation)
    end

    it "derives the operation from the current tool record" do
      tenant.ensure_core_resources!
      connector = create(:connector, :sql_database, tenant:)
      tool = create(
        :tool,
        :enabled,
        operation:,
        toolable: Tools::SqlQuery.new(connector_id: connector.id, llm_config_source: "inherit"),
      )

      context = described_class.build(
        ui_context: {
          "current_object" => {
            "class_name" => "Tool",
            "type" => "Tool",
            "id" => tool.id,
          },
        },
        agent: build(:agent, operation: tenant.headquarter_operation),
      )

      expect(context.tenant).to eq(tenant)
      expect(context.operation).to eq(operation)
    end

    it "derives the operation from the current rag flow record" do
      tenant.ensure_core_resources!
      rag_flow = create(:rag_flow, operation:)

      context = described_class.build(
        ui_context: {
          "current_object" => {
            "class_name" => "RagFlow",
            "type" => "Rag flow",
            "id" => rag_flow.id,
          },
        },
        agent: build(:agent, operation: tenant.headquarter_operation),
      )

      expect(context.tenant).to eq(tenant)
      expect(context.operation).to eq(operation)
    end
  end

  describe "private helper behavior" do
    let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
    let(:operation) { tenant.default_operation }
    let(:context) { described_class.new(ui_context: nil) }

    it "returns operation records directly" do
      expect(context.send(:direct_record_operation, operation)).to eq(operation)
    end

    it "returns nil when skill-scoped records do not expose a catalog operation" do
      expect(context.send(:skill_catalog_operation, Struct.new(:skill_catalog).new(nil))).to be_nil
    end

    it "returns nil when records do not expose skill catalog state" do
      expect(context.send(:skill_catalog_operation, Object.new)).to be_nil
    end

    it "handles non-test-suite, mission-backed, and empty test-suite fallbacks", :aggregate_failures do
      agent_suite = build_stubbed(:test_suite, agent: create(:agent, operation:), mission: nil)
      mission_suite = build_stubbed(:test_suite, agent: nil, mission: create(:mission, operation:))
      empty_suite = build_stubbed(:test_suite, agent: nil, mission: nil)

      expect(context.send(:test_suite_operation, Object.new)).to be_nil
      expect(context.send(:test_suite_operation, agent_suite)).to eq(operation)
      expect(context.send(:test_suite_operation, mission_suite)).to eq(operation)
      expect(context.send(:test_suite_operation, empty_suite)).to be_nil
    end

    it "returns false and nil for unknown model matches and scopes", :aggregate_failures do
      expect(context.send(:current_object_matches?, { "type" => "Unknown" }, "NotARealModel")).to be(false)
      expect(context.send(:current_object_scope, "Unknown", tenant)).to be_nil
    end
  end
end
