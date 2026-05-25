# frozen_string_literal: true

module CostDesigner
  module CostLimitLookup
    private

    def resolve_cost_limit(cost_limit_id)
      identifier = cost_limit_id.to_s.strip
      return nil if identifier.blank?

      tenant.cost_limits.find_by(id: identifier) || unique_name_match(identifier) || missing_cost_limit!(identifier)
    end

    def unique_name_match(identifier)
      matches = tenant.cost_limits.where("LOWER(cost_limits.name) = ?", identifier.downcase).limit(2).to_a
      return matches.first if matches.one?
      return nil if matches.empty?

      raise ActiveRecord::RecordNotFound, "Multiple cost limits named '#{identifier}' were found. Pass the ID."
    end

    def missing_cost_limit!(identifier)
      raise ActiveRecord::RecordNotFound, "Cost limit '#{identifier}' was not found."
    end

    def tenant
      @runtime_context&.tenant || Current.tenant || Tenant.default_tenant
    end

    def operation
      @runtime_context&.operation || Current.operation || tenant&.default_operation
    end
  end
end
