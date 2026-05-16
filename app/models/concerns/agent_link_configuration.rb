# frozen_string_literal: true

module AgentLinkConfiguration
  extend ActiveSupport::Concern

  def tool_ids
    Array(configuration["tool_ids"]).map(&:to_i)
  end

  def tool_ids=(value)
    self.configuration = (configuration || {}).merge("tool_ids" => Array(value).compact_blank.map(&:to_i))
  end

  alias assigned_tool_ids tool_ids
  alias assigned_tool_ids= tool_ids=

  def assigned_tools
    return Tool.none if tool_ids.empty?

    return Tool.where(id: tool_ids) unless respond_to?(:operation_id)

    Tool.where(id: tool_ids, operation_id:)
  end

  def subagent_ids
    Array(configuration["subagent_ids"]).map(&:to_i)
  end

  def subagent_ids=(value)
    self.configuration = (configuration || {}).merge("subagent_ids" => Array(value).compact_blank.map(&:to_i))
  end

  def subagents
    return Agent.none if subagent_ids.empty?

    return Agent.where(id: subagent_ids) unless respond_to?(:operation_id)

    Agent.where(id: subagent_ids, operation_id:)
  end

  def skill_catalog_ids
    Array(configuration["skill_catalog_ids"]).map(&:to_i)
  end

  def skill_catalog_ids=(value)
    self.configuration = (configuration || {}).merge("skill_catalog_ids" => Array(value).compact_blank.map(&:to_i))
  end

  def skill_catalogs
    return SkillCatalog.none if skill_catalog_ids.empty?

    return SkillCatalog.where(id: skill_catalog_ids) unless respond_to?(:operation_id)

    SkillCatalog.where(id: skill_catalog_ids, operation_id:)
  end

  def parent_agents
    Agent.where("configuration->'subagent_ids' @> ?", [id].to_json)
  end
end
