# frozen_string_literal: true

require "rails_helper"

RSpec.describe SkillCatalogDesigner::ReadSkillCatalogTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:skill_catalog) do
    create(
      :skill_catalog,
      operation:,
      name: "Support Playbooks",
      description: "Support knowledge for operators",
    )
  end
  let(:runtime_context) do
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
    create(:skill, skill_catalog:, name: "triage-ticket")
    create(:skill, skill_catalog:, name: "close-loop")

    agent = create(:agent, operation:, name: "Support Agent", model_id: "gpt-4.1")
    agent.skill_catalog_ids = [skill_catalog.id]
    agent.save!
  end

  describe "#name" do
    it "returns read_skill_catalog" do
      expect(described_class.new(runtime_context:).name).to eq("read_skill_catalog")
    end
  end

  describe "#execute" do
    it "reads the current skill catalog details and editable fields" do
      result = described_class.new(runtime_context:, current_skill_catalog: skill_catalog).execute

      expect(result).to include(
        "## Skill Catalog",
        "Support Playbooks",
        "## Skills",
        "triage-ticket",
        "close-loop",
        "## Assigned Agents",
        "Support Agent",
        "## Source Metadata",
        "{}",
        "## Editable Attribute Keys",
        "`name`",
        "`description`",
        "Use `read_skill`/`manage_skill` for individual skills.",
        "Use `manage_skill_catalog_action` for import, restore, and agent assignment flows.",
      )
    end

    it "finds a skill catalog by id inside the current operation" do
      foreign_catalog = create(:skill_catalog, operation: create(:operation, tenant:), name: "Foreign Catalog")
      tool = described_class.new(runtime_context:)

      expect(tool.execute(skill_catalog_id: skill_catalog.id)).to include("Support Playbooks")
      expect(tool.execute(skill_catalog_id: foreign_catalog.id))
        .to eq("Error: Skill catalog '#{foreign_catalog.id}' was not found.")
    end

    it "finds a skill catalog by unique name inside the current operation" do
      tool = described_class.new(runtime_context:)

      expect(tool.execute(skill_catalog_id: skill_catalog.name)).to include("Support Playbooks")
    end

    it "uses the current page context when the current skill catalog is not passed explicitly" do
      ui_context = {
        "current_object" => {
          "type" => "SkillCatalog",
          "class_name" => "SkillCatalog",
          "id" => skill_catalog.id,
          "slug" => skill_catalog.slug,
        },
      }
      tool = described_class.new(runtime_context: runtime_context.with(ui_context:))

      expect(tool.execute).to include("Support Playbooks")
    end

    it "scopes skill catalog lookup by tenant when no runtime operation is present" do
      visible_catalog = create(:skill_catalog, operation:, name: "Tenant Catalog")
      foreign_tenant = create(:tenant).tap(&:ensure_core_resources!)
      foreign_catalog = create(
        :skill_catalog,
        operation: foreign_tenant.default_operation,
        name: "Foreign Tenant Catalog",
      )
      tool = described_class.new(runtime_context: runtime_context.with(operation: nil))

      expect(tool.execute(skill_catalog_id: visible_catalog.id)).to include("Tenant Catalog")
      expect(tool.execute(skill_catalog_id: foreign_catalog.id))
        .to eq("Error: Skill catalog '#{foreign_catalog.id}' was not found.")
    end

    it "asks for an id or slug when a tenant-scoped skill catalog name is ambiguous" do
      create(:skill_catalog, operation:, name: "Shared Catalog")
      create(:skill_catalog, operation: create(:operation, tenant:), name: "Shared Catalog")
      tool = described_class.new(runtime_context: runtime_context.with(operation: nil))

      expect(tool.execute(skill_catalog_id: "Shared Catalog")).to eq(
        "Error: Multiple skill catalogs named 'Shared Catalog' were found. Pass the numeric ID or slug instead.",
      )
    end

    it "renders builtin catalog metadata when present" do
      builtin_catalog = create(
        :skill_catalog,
        :builtin,
        operation:,
        name: "Builtin Guides",
        source_metadata: { "builtin_key" => "undercover-agents-skills" },
      )
      tool = described_class.new(runtime_context:, current_skill_catalog: builtin_catalog)

      expect(tool.execute).to include("- Built-in key: `undercover-agents-skills`")
    end

    it "rescues unexpected errors while rendering" do
      tool = described_class.new(runtime_context:, current_skill_catalog: skill_catalog)
      allow(tool).to receive(:summary_section).and_raise(StandardError, "boom")

      expect(tool.execute).to eq("Error reading skill catalog: boom")
    end

    it "returns a helpful message when there is no current skill catalog" do
      result = described_class.new(runtime_context:).execute
      expected_message = "No current skill catalog is available. Pass skill_catalog_id after creating one or " \
                         "open a skill catalog page first."

      expect(result).to eq(expected_message)
    end

    it "returns the same helpful message when runtime context is missing" do
      expected_message = "No current skill catalog is available. Pass skill_catalog_id after creating one or " \
                         "open a skill catalog page first."

      expect(described_class.new(runtime_context: nil).execute).to eq(expected_message)
    end
  end

  describe "fallback accessors" do
    around do |example|
      original_tenant = Current.tenant
      Current.tenant = nil
      example.run
      Current.tenant = original_tenant
    end

    it "reads the tenant from runtime context when present" do
      expect(described_class.new(runtime_context:).send(:tenant)).to eq(tenant)
    end

    it "falls back from current skill catalog, Current.tenant, and default tenant" do
      Current.tenant = tenant
      tool_with_current_catalog = described_class.new(runtime_context: nil, current_skill_catalog: skill_catalog)

      expect(tool_with_current_catalog.send(:tenant)).to eq(tenant)
      expect(described_class.new(runtime_context: nil).send(:tenant)).to eq(tenant)

      Current.tenant = nil
      allow(Tenant).to receive(:default_tenant).and_return(tenant)

      expect(described_class.new(runtime_context: nil).send(:tenant)).to eq(tenant)
    end

    it "falls back from current skill catalog to resolve the operation" do
      expect(described_class.new(runtime_context: nil, current_skill_catalog: skill_catalog).send(:operation))
        .to eq(operation)
      expect(described_class.new(runtime_context: nil).send(:operation)).to be_nil
    end
  end
end
