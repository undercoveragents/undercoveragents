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
  factory :connectors_llm_provider, class: "Connector" do
    tenant { Tenant.order(:id).first || association(:tenant) }
    connector_type { "llm_provider" }
    sequence(:name) { |n| "LLM Provider #{n}" }
    provider { "openai" }
    api_key { "sk-test-#{SecureRandom.hex(24)}" }
    request_timeout { 120 }
    max_retries { 3 }
    retry_interval { 0.1 }
    retry_backoff_factor { 2 }
    retry_interval_randomness { 0.5 }

    trait :openai do
      provider { "openai" }
      api_key { "sk-test-#{SecureRandom.hex(24)}" }
    end

    trait :anthropic do
      provider { "anthropic" }
      api_key { "sk-ant-test-#{SecureRandom.hex(24)}" }
    end

    trait :gemini do
      provider { "gemini" }
      api_key { "gemini-key-12345" }
    end

    trait :bedrock do
      provider { "bedrock" }
      api_key { "AKIAIOSFODNN7EXAMPLE" }
      secret_key { "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" }
      region { "us-east-1" }
    end

    trait :azure do
      provider { "azure" }
      api_base { "https://my-resource.openai.azure.com" }
      api_key { "azure-test-#{SecureRandom.hex(16)}" }
    end

    trait :ollama do
      provider { "ollama" }
      api_key { nil }
      api_base { "http://localhost:11434/v1" }
    end

    trait :with_proxy do
      http_proxy { "http://proxy.example.com:8080" }
    end

    trait :high_timeout do
      request_timeout { 300 }
      max_retries { 5 }
    end
  end
end
