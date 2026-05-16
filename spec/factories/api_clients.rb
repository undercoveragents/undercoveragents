# frozen_string_literal: true

# == Schema Information
#
# Table name: api_clients
# Database name: primary
#
#  id           :bigint           not null, primary key
#  access_scope :string           default("all"), not null
#  description  :text
#  enabled      :boolean          default(TRUE), not null
#  last_used_at :datetime
#  name         :string           not null
#  token_digest :string           not null
#  token_prefix :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  tenant_id    :bigint           not null
#
# Indexes
#
#  index_api_clients_on_enabled             (enabled)
#  index_api_clients_on_tenant_id           (tenant_id)
#  index_api_clients_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#  index_api_clients_on_token_prefix        (token_prefix) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id)
#
FactoryBot.define do
  factory :api_client do
    tenant { Tenant.order(:id).first || association(:tenant) }
    sequence(:name) { |n| "API Client #{n}" }
    description { "A test API client" }
    access_scope { "all" }
    enabled { true }

    transient do
      raw_token { nil }
    end

    after(:build) do |api_client, evaluator|
      if api_client.token_prefix.blank?
        token_data = ApiClient.generate_token
        api_client.token_prefix = token_data[:prefix]
        api_client.token_digest = token_data[:digest]
        evaluator.instance_variable_set(:@raw_token, token_data[:raw_token])
      end
    end

    trait :scoped do
      access_scope { "scoped" }
    end

    trait :disabled do
      enabled { false }
    end
  end
end
