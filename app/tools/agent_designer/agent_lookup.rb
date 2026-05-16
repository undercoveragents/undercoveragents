# frozen_string_literal: true

module AgentDesigner
  module AgentLookup
    private

    def resolve_agent(agent_id)
      return @current_agent if agent_id.blank? && @current_agent.is_a?(Agent)

      identifier = agent_id.to_s.strip
      return nil if identifier.blank?

      scope = agent_scope
      scope.find_by(id: identifier) || scope.find_by(slug: identifier) || unique_name_match(scope, identifier) ||
        missing_record!(identifier)
    end

    def unique_name_match(scope, identifier)
      matches = scope.where("LOWER(agents.name) = ?", identifier.downcase).limit(2).to_a
      return matches.first if matches.one?
      return nil if matches.empty?

      raise ActiveRecord::RecordNotFound,
            "Multiple agents named '#{identifier}' were found. Pass the numeric ID or slug instead."
    end

    def missing_record!(identifier)
      raise ActiveRecord::RecordNotFound, "Agent '#{identifier}' was not found."
    end

    def agent_scope
      scope = Agent.includes(:operation)
      scope = scope.where(operation:) if operation
      scope = scope.joins(:operation).where(operations: { tenant_id: tenant.id }) if operation.nil? && tenant
      scope.ordered
    end

    def missing_agent_message
      "No current agent is available. Pass agent_id after creating one or open an agent page first."
    end

    def tenant
      @runtime_context&.tenant || @current_agent&.tenant || Current.tenant || Tenant.default_tenant
    end

    def operation
      @runtime_context&.operation || @current_agent&.operation
    end
  end
end
