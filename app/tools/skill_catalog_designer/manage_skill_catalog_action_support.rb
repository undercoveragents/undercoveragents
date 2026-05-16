# frozen_string_literal: true

module SkillCatalogDesigner
  module ManageSkillCatalogActionSupport
    private

    def catalog_action_message(skill_catalog:, action:, refreshed:, agent: nil, result: nil)
      [
        "Skill catalog action completed.",
        "- Skill Catalog: #{skill_catalog.name} (`#{skill_catalog.id}`)",
        "- Action: `#{action}`",
        ("- Agent: #{agent.name} (`#{agent.id}`)" if agent),
        ("- Result: #{result}" if result.present?),
        ("Current page refresh started to show the saved skill catalog." if refreshed),
      ].compact.join("\n")
    end

    def resolve_agent!(agent_id, selectable:)
      scope = selectable ? scoped_agents.enabled.selectable : scoped_agents

      scope.find_by(id: agent_id) ||
        scope.find_by(slug: agent_id) ||
        raise(ActiveRecord::RecordNotFound, "Agent '#{agent_id}' was not found.")
    end

    def restored_builtin_catalog(builtin_key)
      tenant.headquarter_operation.skill_catalogs.builtin
            .where("source_metadata ->> 'builtin_key' = ?", builtin_key)
            .first!
    end

    def scoped_agents
      Agent.where(operation:).ordered
    end

    def tenant
      return @runtime_context.tenant if @runtime_context&.tenant
      return @current_skill_catalog.operation.tenant if @current_skill_catalog&.operation

      Current.tenant || Tenant.default_tenant
    end

    def operation
      @runtime_context&.operation || @current_skill_catalog&.operation || tenant.default_operation
    end
  end
end
