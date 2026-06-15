# frozen_string_literal: true

module ChatCostAccounting
  extend ActiveSupport::Concern

  # Calculates the total cost of the chat in USD based on token usage and model pricing.
  # Returns nil if no model is associated or if pricing information is unavailable.
  # @return [BigDecimal, nil] The total cost in USD
  def calculate_cost
    messages.sum(&:effective_cost)
  end

  def snapshot_cost
    messages.sum(:cost_usd)
  end

  def check_cost_limits!
    assign_cost_attribution
    return true unless tenant

    Costs::LimitEnforcer.check!(
      tenant:,
      operation:,
      user:,
      agent:,
      mission:,
      channel:,
      model_id: self[:model_id],
      execution_context:,
    )
  end

  private

  def assign_cost_attribution
    inferred_operation = cost_attribution_operation
    self.operation ||= inferred_operation
    self.tenant ||= cost_attribution_tenant(inferred_operation)
  end

  def cost_attribution_operation
    [
      operation,
      parent_chat&.operation,
      agent&.operation,
      mission&.operation,
      channel&.operation,
      Current.operation,
    ].find(&:present?)
  end

  def cost_attribution_tenant(inferred_operation)
    tenant_sources(inferred_operation).find(&:present?)
  end

  def tenant_sources(inferred_operation)
    [
      tenant,
      inferred_operation&.tenant,
      parent_chat&.tenant,
      user&.tenant,
      record_operation_tenant(agent),
      record_operation_tenant(mission),
      channel&.tenant,
      Current.tenant,
    ]
  end

  def record_operation_tenant(record)
    record&.operation&.tenant
  end
end
