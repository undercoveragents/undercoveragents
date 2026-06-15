# frozen_string_literal: true

# == Schema Information
#
# Table name: cost_limits
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  amount_usd                :decimal(18, 6)   not null
#  description               :text
#  enabled                   :boolean          default(TRUE), not null
#  enforcement_mode          :string           default("warn_only"), not null
#  name                      :string           not null
#  period                    :string           not null
#  target_key                :string
#  target_type               :string           not null
#  warning_threshold_percent :integer          default(80), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  operation_id              :bigint
#  target_id                 :bigint
#  tenant_id                 :bigint           not null
#
# Indexes
#
#  idx_cost_limits_on_target                        (tenant_id,target_type,target_id,target_key)
#  index_cost_limits_on_operation_id                (operation_id)
#  index_cost_limits_on_tenant_id                   (tenant_id)
#  index_cost_limits_on_tenant_id_and_enabled       (tenant_id,enabled)
#  index_cost_limits_on_tenant_id_and_operation_id  (tenant_id,operation_id)
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#  fk_rails_...  (tenant_id => tenants.id)
#
FactoryBot.define do
  factory :cost_limit do
    tenant { Tenant.order(:id).first || association(:tenant) }
    name { "Monthly tenant budget" }
    target_type { "tenant" }
    period { "month" }
    amount_usd { 25.0 }
    warning_threshold_percent { 80 }
    enforcement_mode { "warn_only" }
    enabled { true }

    trait :hard_stop do
      enforcement_mode { "hard_stop" }
    end

    trait :for_operation do
      operation { association(:operation, tenant:) }
      target_type { "operation" }
      name { "Operation budget" }
    end

    trait :for_agent do
      transient do
        agent_record { nil }
      end

      target_type { "agent" }
      name { "Agent budget" }

      before(:create) do |limit, evaluator|
        agent_operation = limit.operation || create(:operation, tenant: limit.tenant)
        agent = evaluator.agent_record || create(:agent, operation: agent_operation)
        limit.operation = agent.operation
        limit.target_id = agent.id
      end
    end

    trait :for_execution_context do
      target_type { "execution_context" }
      target_key { "application" }
      name { "Application chat budget" }
    end
  end
end
