# frozen_string_literal: true

FactoryBot.define do
  factory :connectors_brave_search, class: "Connector" do
    tenant { Tenant.order(:id).first || association(:tenant) }
    connector_type { "brave_search" }
    sequence(:name) { |n| "Brave Search #{n}" }
    api_key { "brave-test-key-#{SecureRandom.hex(12)}" }
  end
end
