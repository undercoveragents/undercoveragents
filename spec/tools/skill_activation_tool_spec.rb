# frozen_string_literal: true

require "rails_helper"

RSpec.describe SkillActivationTool do
  describe "#name" do
    it "returns the runtime tool name" do
      tool = described_class.new(instance_double(Skills::AssignedRegistry, find: nil))

      expect(tool.name).to eq("activate_skill")
    end
  end

  describe "#execute" do
    it "returns a not found message for unknown skills" do
      tool = described_class.new(instance_double(Skills::AssignedRegistry, find: nil))

      expect(tool.execute(skill_identifier: "missing")).to eq(
        "The selected skill could not be found. Call list_available_skills to inspect installed skill identifiers.",
      )
    end

    it "renders the canonical skill markdown and bundled resource list" do
      skill_catalog = create(:skill_catalog)
      skill = create(:skill, skill_catalog:)
      create(:skill_resource, skill:, relative_path: "references/checklist.md")
      tool = described_class.new(build_registry(skill_catalog))

      result = tool.execute(skill_identifier: "#{skill_catalog.slug}/#{skill.id}")

      expect(result).to include("<skill_content")
      expect(result).to include(skill.skill_markdown)
      expect(result).to include("references/checklist.md")
    end

    it "omits the resource listing when the skill has no bundled files" do
      skill_catalog = create(:skill_catalog)
      skill = create(:skill, skill_catalog:)
      tool = described_class.new(build_registry(skill_catalog))

      result = tool.execute(skill_identifier: "#{skill_catalog.slug}/#{skill.id}")

      expect(result).to include("<skill_content")
      expect(result).not_to include("<skill_resources>")
    end
  end

  def build_registry(skill_catalog)
    agent = create(:agent, operation: skill_catalog.operation)
    agent.update!(skill_catalog_ids: [skill_catalog.id])
    Skills::AssignedRegistry.new(agent)
  end
end
