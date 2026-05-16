# frozen_string_literal: true

require "rails_helper"

RSpec.describe BuiltinSkills::Synchronizer do
  describe ".ensure_present!" do
    it "creates builtin catalogs and skills in Headquarter" do
      described_class.ensure_present!(keys: ["undercover-agents-missions"])

      catalog = SkillCatalog.find_by!(source_type: "builtin")
      skill = catalog.skills.builtin.find { |item| item.builtin_key == "mission-designer-workbench" }

      expect(catalog.operation.name).to eq(Operation::HEADQUARTER_NAME)
      expect(catalog.builtin_key).to eq("undercover-agents-missions")
      expect(skill.builtin_key).to eq("mission-designer-workbench")
      expect(skill.skill_identifier).to eq("undercover-agents-missions/mission-designer-workbench")
      expect(skill.skill_resources.pluck(:relative_path)).to include("references/mission-review-checklist.md")
    end

    it "does not overwrite editable customizations during a normal sync" do
      described_class.ensure_present!(keys: ["undercover-agents-missions"])
      catalog = SkillCatalog.find_by!(source_type: "builtin")
      skill = catalog.skills.builtin.find { |item| item.builtin_key == "mission-designer-workbench" }

      catalog.update!(name: "Customized Catalog")
      skill.update!(instructions: "Custom instructions")

      described_class.ensure_present!(keys: ["undercover-agents-missions"])

      expect(catalog.reload.name).to eq("Customized Catalog")
      expect(skill.reload.instructions).to eq("Custom instructions")
    end

    it "removes stale builtin catalogs during a full sync" do
      tenant = Tenant.default_tenant.tap(&:ensure_core_resources!)
      headquarter = tenant.headquarter_operation
      stale_catalog = create(
        :skill_catalog,
        :builtin,
        operation: headquarter,
        source_metadata: { "builtin_key" => "stale-catalog" },
      )

      described_class.ensure_present!(tenant:)

      expect(SkillCatalog.find_by(id: stale_catalog.id)).to be_nil
    end

    it "removes stale builtin skills while syncing an existing builtin catalog" do
      tenant = create(:tenant)
      tenant.ensure_core_resources!
      described_class.ensure_present!(keys: ["undercover-agents-missions"], tenant:)
      catalog = tenant.headquarter_operation.skill_catalogs.builtin.find_by!(name: "Missions")
      stale_skill = create(
        :skill,
        :builtin,
        skill_catalog: catalog,
        name: "stale-skill",
        source_metadata: { "builtin_key" => "stale-skill" },
      )

      described_class.ensure_present!(keys: ["undercover-agents-missions"], tenant:)

      expect(Skill.find_by(id: stale_skill.id)).to be_nil
    end

    it "keeps expected builtin catalogs during a full sync" do
      tenant = create(:tenant)
      tenant.ensure_core_resources!
      described_class.ensure_present!(keys: ["undercover-agents-missions"], tenant:)
      catalog = tenant.headquarter_operation.skill_catalogs.builtin.find_by!(name: "Missions")

      described_class.ensure_present!(tenant:)

      expect(SkillCatalog.exists?(catalog.id)).to be(true)
    end

    it "keeps expected builtin skills during a full sync" do
      tenant = create(:tenant)
      tenant.ensure_core_resources!
      described_class.ensure_present!(keys: ["undercover-agents-missions"], tenant:)
      catalog = tenant.headquarter_operation.skill_catalogs.builtin.find_by!(name: "Missions")
      skill = catalog.skills.builtin.find { |item| item.builtin_key == "mission-designer-workbench" }

      described_class.ensure_present!(tenant:)

      expect(skill).to be_present
      expect(Skill.exists?(skill.id)).to be(true)
    end

    it "raises when requested builtin catalog keys are unknown" do
      allow(BuiltinSkills::DefinitionLoader).to receive(:load_all).and_return([])

      expect do
        described_class.ensure_present!(keys: ["missing-catalog"])
      end.to raise_error("Unknown builtin skill catalog keys: missing-catalog")
    end
  end

  describe ".restore!" do
    it "restores builtin catalog and skill content to the shipped defaults" do
      described_class.ensure_present!(keys: ["undercover-agents-missions"])
      catalog = SkillCatalog.find_by!(source_type: "builtin")
      skill = catalog.skills.builtin.find { |item| item.builtin_key == "mission-designer-workbench" }
      definition = BuiltinSkills::DefinitionLoader.load_for(["undercover-agents-missions"]).first
      skill_definition = definition.skills.find { |item| item.key == "mission-designer-workbench" }

      catalog.update!(name: "Customized Catalog")
      skill.update!(instructions: "Custom instructions")

      described_class.restore!("undercover-agents-missions")

      expect(catalog.reload.name).to eq(definition.name)
      expect(skill.reload.instructions).to eq(skill_definition.instructions)
    end
  end

  describe ".restore_all!" do
    it "returns an empty result when no definitions are loaded" do
      allow(BuiltinSkills::DefinitionLoader).to receive(:load_all).and_return([])

      result = described_class.restore_all!

      expect(result.created_keys).to eq([])
      expect(result.restored_keys).to eq([])
    end
  end

  describe "private cleanup helpers" do
    it "clears inherited ordering before batching stale builtin skills" do
      synchronizer = described_class.new
      catalog = create(:skill_catalog)
      create_builtin_skill(catalog, "kept-skill")
      stale_skill = create_builtin_skill(catalog, "stale-skill")
      definition = instance_double(BuiltinSkills::SkillDefinition, key: "kept-skill")

      skills_relation = catalog.skills
      builtin_relation = skills_relation.builtin

      allow(catalog).to receive(:skills).and_return(skills_relation)
      allow(skills_relation).to receive(:builtin).and_return(builtin_relation)
      allow(builtin_relation).to receive(:reorder).and_call_original

      synchronizer.send(:destroy_stale_skills!, catalog, [definition])

      expect(builtin_relation).to have_received(:reorder).with(nil)
      expect(Skill.exists?(stale_skill.id)).to be(false)
    end
  end

  def create_builtin_skill(catalog, key)
    create(:skill, :builtin, skill_catalog: catalog, source_metadata: { "builtin_key" => key })
  end
end
