# frozen_string_literal: true

module HasSkillCatalogs
  extend ActiveSupport::Concern

  def skill_registry
    @skill_registry ||= Skills::AssignedRegistry.new(self)
  end

  def skill_tools
    registry = skill_registry
    return [] unless registry.any?

    tools = [SkillListTool.new(registry), SkillActivationTool.new(registry)]
    tools << SkillResourceReaderTool.new(registry) if registry.any_resources?
    tools
  end

  def skill_system_prompt_addition
    Skills::PromptBuilder.new(skill_registry).build
  end
end
