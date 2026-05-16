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
  factory :connectors_authentication, class: "Connector" do
    tenant { Tenant.order(:id).first || association(:tenant) }
    connector_type { "authentication" }
    sequence(:name) { |n| "Authentication #{n}" }
    provider { "keycloak" }
    site_url { "https://keycloak.example.com" }
    realm { "event-horizon" }
    client_id { "event-horizon-client" }
    client_secret { "super-secret-client-key" }

    trait :google do
      provider { "google" }
      site_url { nil }
      realm { nil }
      client_id { "google-client-id" }
      client_secret { "google-client-secret" }
    end
  end
end
