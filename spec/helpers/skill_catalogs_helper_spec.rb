# frozen_string_literal: true

require "rails_helper"

RSpec.describe SkillCatalogsHelper do
  describe "count labels" do
    it "formats skill, agent, and resource counts" do
      skill_catalog = instance_double(
        SkillCatalog,
        skill_count: 2,
        assigned_agents_count: 1,
        total_resource_count: 3,
      )

      expect(helper.skill_catalog_skill_count_label(skill_catalog)).to eq("2 skills")
      expect(helper.skill_catalog_agent_count_label(skill_catalog)).to eq("1 agent")
      expect(helper.skill_catalog_resource_count_label(skill_catalog)).to eq("3 resources")
    end

    it "handles the opposite singular and plural branches" do
      skill_catalog = instance_double(
        SkillCatalog,
        skill_count: 1,
        assigned_agents_count: 2,
        total_resource_count: 1,
      )

      expect(helper.skill_catalog_skill_count_label(skill_catalog)).to eq("1 skill")
      expect(helper.skill_catalog_agent_count_label(skill_catalog)).to eq("2 agents")
      expect(helper.skill_catalog_resource_count_label(skill_catalog)).to eq("1 resource")
    end
  end

  describe "badge helpers" do
    it "renders source badges for builtin, manual, and imported skills" do
      builtin = instance_double(Skill, builtin?: true, imported?: false)
      imported = instance_double(Skill, builtin?: false, imported?: true)
      manual = instance_double(Skill, builtin?: false, imported?: false)

      expect(helper.skill_source_badge(builtin)).to include("Builtin", "badge-secondary")
      expect(helper.skill_source_badge(imported)).to include("Imported", "badge-info")
      expect(helper.skill_source_badge(manual)).to include("Manual", "badge-success")
    end

    it "renders warning badges only when warnings are present" do
      warned_skill = instance_double(Skill, spec_warnings: ["One", "Two"])
      clean_skill = instance_double(Skill, spec_warnings: [])
      single_warning_skill = instance_double(Skill, spec_warnings: ["One"])

      expect(helper.skill_warning_badge(warned_skill)).to include("2 warnings")
      expect(helper.skill_warning_badge(single_warning_skill)).to include("1 warning")
      expect(helper.skill_warning_badge(clean_skill)).to be_nil
    end
  end

  describe "#skill_resource_icon" do
    it "maps each resource kind to an icon" do
      expect(helper.skill_resource_icon(instance_double(SkillResource,
                                                        resource_kind: "scripts",))).to eq("fa-solid fa-terminal")
      expect(helper.skill_resource_icon(instance_double(SkillResource,
                                                        resource_kind: "references",))).to eq("fa-solid fa-book")
      expect(helper.skill_resource_icon(instance_double(SkillResource,
                                                        resource_kind: "assets",))).to eq("fa-solid fa-photo-film")
      expect(helper.skill_resource_icon(instance_double(SkillResource,
                                                        resource_kind: "other",))).to eq("fa-solid fa-file")
    end
  end
end
