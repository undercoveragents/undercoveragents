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
#  enabled        :boolean          default(FALSE), not null
#  name           :string           not null
#  slug           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_connectors_on_connector_type           (connector_type)
#  index_connectors_on_enabled                  (enabled)
#  index_connectors_on_name                     (name) UNIQUE
#  index_connectors_on_slug                     (slug) UNIQUE
#  index_connectors_on_telegram_webhook_secret  (((configuration ->> 'webhook_secret'::text))) UNIQUE WHERE (((connector_type)::text = 'telegram'::text) AND ((configuration ->> 'webhook_secret'::text) IS NOT NULL))
#
FactoryBot.define do
  factory :connectors_sql_database, class: "Connector" do
    tenant { Tenant.order(:id).first || association(:tenant) }
    connector_type { "sql_database" }
    sequence(:name) { |n| "SQL Database #{n}" }
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
end
