# frozen_string_literal: true

require "rails_helper"

RSpec.describe SkillCatalogDesigner::ReadSkillTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:skill_catalog) { create(:skill_catalog, operation:, name: "Support Playbooks") }
  let(:skill) do
    create(
      :skill,
      skill_catalog:,
      name: "triage-ticket",
      metadata: { "topic" => "support" },
      source_metadata: { "directory_name" => "triage-ticket" },
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
    create(:skill_resource, skill:, relative_path: "references/checklist.md")
  end

  describe "#name" do
    it "returns read_skill" do
      expect(described_class.new(runtime_context:).name).to eq("read_skill")
    end
  end

  describe "#execute" do
    it "reads the current skill details, metadata, resources, and editable fields" do
      result = described_class.new(runtime_context:, current_skill: skill).execute

      expect(result).to include(
        "## Skill",
        "triage-ticket",
        "Support Playbooks",
        "## Metadata",
        '"topic": "support"',
        "## Resources",
        "references/checklist.md",
        "## Editable Attribute Keys",
        "`instructions`",
        "`metadata`",
      )
    end

    it "uses the current page context when the current skill is not passed explicitly" do
      ui_context = {
        "current_object" => {
          "type" => "Skill",
          "class_name" => "Skill",
          "id" => skill.id,
        },
      }
      contextual_runtime_context = BuiltinTools::RuntimeContext::Context.new(
        agent: nil,
        chat: nil,
        mission: nil,
        ui_context:,
        user: nil,
        tenant:,
        operation:,
      )

      result = described_class.new(runtime_context: contextual_runtime_context).execute

      expect(result).to include("triage-ticket")
    end

    it "returns a helpful message when there is no current skill" do
      expect(described_class.new(runtime_context:).execute).to eq(
        "No current skill is available. Open a skill page first or pass skill_id.",
      )
    end
  end
end
