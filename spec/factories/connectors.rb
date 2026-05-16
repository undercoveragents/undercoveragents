# frozen_string_literal: true

# == Schema Information
#
# Table name: connectors
# Database name: primary
#
#  id             :bigint           not null, primary key
#  configuration  :jsonb            not null
#  connector_type :string           not null
#  description    :text
#  enabled        :boolean          default(TRUE), not null
#  name           :string           not null
#  slug           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  tenant_id      :bigint           not null
#
# Indexes
#
#  index_connectors_on_connector_type      (connector_type)
#  index_connectors_on_enabled             (enabled)
#  index_connectors_on_slug                (slug) UNIQUE
#  index_connectors_on_tenant_id           (tenant_id)
#  index_connectors_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id)
#
FactoryBot.define do
  factory :connector do
    tenant { Tenant.order(:id).first || association(:tenant) }
    name { Faker::Lorem.unique.words(number: 3).join(" ").titleize }
    description { Faker::Lorem.sentence }
    enabled { false }

    trait :sql_database do
      connector_type { "sql_database" }
      adapter_type { "postgresql" }
      host { Faker::Internet.ip_v4_address }
      port { 5432 }
      database_name { Faker::Lorem.word }
      schema_name { "public" }
      username { Faker::Internet.username }
      encrypted_password { Faker::Internet.password }
      ssl_enabled { false }
      pool_size { 5 }
      timeout { 5000 }
      read_only { true }
      max_results { 100 }
    end

    trait :llm_provider do
      connector_type { "llm_provider" }
      provider { "openai" }
      api_key { "sk-test-#{SecureRandom.hex(24)}" }
      request_timeout { 120 }
      max_retries { 3 }
      retry_interval { 0.1 }
      retry_backoff_factor { 2 }
      retry_interval_randomness { 0.5 }
    end

    trait :mcp_server do
      connector_type { "mcp_server" }
      transport_type { "stdio" }
      command { "npx" }
      args { ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"] }
      env_vars { {} }
      headers { {} }
      request_timeout { 8000 }
    end

    trait :authentication do
      connector_type { "authentication" }
      provider { "keycloak" }
      site_url { "https://keycloak.example.com" }
      realm { "event-horizon" }
      client_id { "event-horizon-client" }
      client_secret { "super-secret-client-key" }
    end

    trait :enabled do
      enabled { true }
    end

    trait :disabled do
      enabled { false }
    end
  end
end
