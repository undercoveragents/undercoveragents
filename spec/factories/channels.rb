# frozen_string_literal: true

# == Schema Information
#
# Table name: channels
# Database name: primary
#
#  id            :bigint           not null, primary key
#  channel_type  :string           not null
#  configuration :jsonb            not null
#  default       :boolean          default(FALSE), not null
#  description   :text
#  enabled       :boolean          default(TRUE), not null
#  name          :string           not null
#  slug          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  connector_id  :bigint
#  tenant_id     :bigint           not null
#
# Indexes
#
#  index_channels_on_channel_type        (channel_type)
#  index_channels_on_connector_id        (connector_id)
#  index_channels_on_default             (default)
#  index_channels_on_enabled             (enabled)
#  index_channels_on_slug                (slug) UNIQUE
#  index_channels_on_tenant_id           (tenant_id)
#  index_channels_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (connector_id => connectors.id)
#  fk_rails_...  (tenant_id => tenants.id)
#
FactoryBot.define do
  factory :channel do
    tenant
    name { Faker::Company.unique.name }
    description { Faker::Lorem.sentence }
    channel_type { "client" }
    configuration { {} }
    enabled { true }
    default { false }

    trait :client do
      channel_type { "client" }
    end

    trait :api do
      channel_type { "api" }
    end
  end

  factory :channel_target do
    channel
    target { association(:agent, operation: association(:operation, tenant: channel.tenant)) }
    configuration { {} }
    default { false }
    position { 0 }

    trait :mission do
      channel { association(:channel, :api) }
      target { association(:mission, operation: association(:operation, tenant: channel.tenant)) }
    end
  end

  factory :channel_identity do
    channel
    sequence(:external_user_id) { |n| "external-user-#{n}" }
    external_username { Faker::Internet.username }
    metadata { {} }
  end

  factory :channel_credential do
    channel { association(:channel, :api) }
    credential_type { "bearer_token" }
    name { Faker::App.unique.name }
    metadata { {} }
  end

  factory :channel_conversation do
    channel
    external_conversation_id { SecureRandom.uuid }
    external_thread_id { "" }
    metadata { {} }
  end
end
