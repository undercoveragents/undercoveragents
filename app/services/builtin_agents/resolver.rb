# frozen_string_literal: true

module BuiltinAgents
  class Resolver
    def self.find!(key, tenant: Current.tenant || Tenant.default_tenant)
      agent = Agent.find_builtin_by_key(key, tenant:)
      return agent if agent

      BuiltinAgents::Synchronizer.ensure_present!(keys: [key], tenant:)
      Agent.find_builtin_by_key(key, tenant:) || raise(ActiveRecord::RecordNotFound, "Builtin agent not found: #{key}")
    end
  end
end
