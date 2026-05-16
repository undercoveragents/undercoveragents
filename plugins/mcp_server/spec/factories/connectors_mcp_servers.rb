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
  factory :connectors_mcp_server, class: "Connector" do
    tenant { Tenant.order(:id).first || association(:tenant) }
    connector_type { "mcp_server" }
    sequence(:name) { |n| "MCP Server #{n}" }
    transport_type { "stdio" }
    command { "npx" }
    args { ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"] }
    env_vars { {} }
    headers { {} }
    request_timeout { 8000 }

    trait :stdio do
      transport_type { "stdio" }
      command { "npx" }
      args { ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"] }
    end

    trait :stdio_github do
      transport_type { "stdio" }
      command { "npx" }
      args { ["-y", "@modelcontextprotocol/server-github"] }
      env_vars { { "GITHUB_PERSONAL_ACCESS_TOKEN" => "ghp_test123" } }
    end

    trait :sse do
      transport_type { "sse" }
      command { nil }
      url { "https://mcp.example.com/sse" }
    end

    trait :sse_with_headers do
      transport_type { "sse" }
      command { nil }
      url { "https://mcp.example.com/sse" }
      headers { { "Authorization" => "Bearer test-token" } }
    end

    trait :streamable_http do
      transport_type { "streamable_http" }
      command { nil }
      url { "https://mcp.example.com/mcp" }
    end

    trait :with_oauth do
      oauth_enabled { true }
      oauth_client_id { "my-client-id" }
      oauth_client_secret { "my-client-secret" }
      oauth_scope { "mcp:read mcp:write" }
      oauth_grant_type { "authorization_code" }
    end

    trait :client_credentials do
      oauth_enabled { true }
      oauth_grant_type { "client_credentials" }
      oauth_client_id { "app-client-id" }
      oauth_client_secret { "app-client-secret" }
      oauth_scope { "mcp:read" }
    end
  end
end
