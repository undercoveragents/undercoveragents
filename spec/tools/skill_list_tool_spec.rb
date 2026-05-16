# frozen_string_literal: true

require "rails_helper"

RSpec.describe SkillListTool do
  describe "#name" do
    it "returns the runtime tool name" do
      tool = described_class.new(instance_double(Skills::AssignedRegistry, entries: []))

      expect(tool.name).to eq("list_available_skills")
    end
  end

  describe "#execute" do
    it "lists installed skills and their identifiers" do
      skill_catalog = create(:skill_catalog, name: "Agents")
      skill = create(:skill, skill_catalog:, name: "agent-playbook")
      create(:skill_resource, skill:, relative_path: "references/checklist.md")
      tool = described_class.new(build_registry(skill_catalog))

      result = tool.execute

      expect(result).to include("Installed skill catalogs: 1")
      expect(result).to include("Installed skills: 1")
      expect(result).to include("<available_skills>")
      expect(result).to include(skill.skill_identifier)
      expect(result).to include("<has_resources>true</has_resources>")
    end

    it "filters by catalog name and query" do
      agents_catalog = create(:skill_catalog, name: "Agents")
      tools_catalog = create(:skill_catalog, name: "Tools", operation: agents_catalog.operation)
      create(:skill, skill_catalog: agents_catalog, name: "agent-playbook", description: "Guide for agents")
      matching_skill = create(
        :skill,
        skill_catalog: tools_catalog,
        name: "widget-tool-guide",
        description: "Guide for tools",
      )
      agent = create(:agent, operation: agents_catalog.operation)
      agent.update!(skill_catalog_ids: [agents_catalog.id, tools_catalog.id])
      tool = described_class.new(Skills::AssignedRegistry.new(agent))

      result = tool.execute(catalog: "Tools", query: "widget")

      expect(result).to include(matching_skill.skill_identifier)
      expect(result).not_to include("agent-playbook")
    end

    it "filters by catalog identifier" do
      agents_catalog = create(:skill_catalog, name: "Agents")
      tools_catalog = create(:skill_catalog, name: "Tools", operation: agents_catalog.operation)
      create(:skill, skill_catalog: agents_catalog, name: "agent-playbook")
      matching_skill = create(:skill, skill_catalog: tools_catalog, name: "tool-playbook")
      agent = create(:agent, operation: agents_catalog.operation)
      agent.update!(skill_catalog_ids: [agents_catalog.id, tools_catalog.id])
      tool = described_class.new(Skills::AssignedRegistry.new(agent))

      result = tool.execute(catalog: tools_catalog.slug)

      expect(result).to include(matching_skill.skill_identifier)
      expect(result).not_to include("agent-playbook")
    end

    it "returns a helpful message when filters match nothing" do
      skill_catalog = create(:skill_catalog, name: "Agents")
      create(:skill, skill_catalog:, name: "agent-playbook")
      tool = described_class.new(build_registry(skill_catalog))

      expect(tool.execute(query: "missing")).to include("No installed skills matched the requested filters")
    end
  end

  def build_registry(skill_catalog)
    agent = create(:agent, operation: skill_catalog.operation)
    agent.update!(skill_catalog_ids: [skill_catalog.id])
    Skills::AssignedRegistry.new(agent)
  end
end
