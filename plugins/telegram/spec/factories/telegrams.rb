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
  factory :connectors_telegram, class: "Connector" do
    tenant { Tenant.order(:id).first || association(:tenant) }
    connector_type { "telegram" }
    sequence(:name) { |n| "Telegram #{n}" }
    bot_token { "#{Faker::Number.number(digits: 10)}:#{SecureRandom.alphanumeric(35)}" }
    bot_username { "test_bot" }

    trait :with_webhook do
      webhook_url { "https://example.com/telegram/webhook/#{SecureRandom.hex(32)}" }
      webhook_secret { SecureRandom.hex(32) }
    end
  end
end

# Add :telegram trait to the main connector factory so plugin specs can use
# build(:connector, :telegram) / create(:connector, :telegram).
FactoryBot.modify do
  factory :connector do
    trait :telegram do
      tenant { Tenant.order(:id).first || association(:tenant) }
      connector_type { "telegram" }
      bot_token { "#{Faker::Number.number(digits: 10)}:#{SecureRandom.alphanumeric(35)}" }
      bot_username { "test_bot" }
    end
  end
end
