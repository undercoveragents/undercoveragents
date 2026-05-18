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
#  operation_id  :bigint           not null
#  tenant_id     :bigint           not null
#
# Indexes
#
#  index_channels_on_channel_type           (channel_type)
#  index_channels_on_connector_id           (connector_id)
#  index_channels_on_default                (default)
#  index_channels_on_enabled                (enabled)
#  index_channels_on_operation_id           (operation_id)
#  index_channels_on_operation_id_and_name  (operation_id,name) UNIQUE
#  index_channels_on_slug                   (slug) UNIQUE
#  index_channels_on_tenant_id              (tenant_id)
#
# Foreign Keys
#
#  fk_rails_...  (connector_id => connectors.id)
#  fk_rails_...  (operation_id => operations.id)
#  fk_rails_...  (tenant_id => tenants.id)
#
FactoryBot.define do
  factory :channel do
    tenant
    operation do
      if tenant&.id.present? && Tenant.exists?(tenant.id)
        tenant.operations.order(created_at: :desc).first || tenant.ensure_core_resources!.default_operation
      else
        association(:operation, tenant:)
      end
    end
    name { Faker::Company.unique.name }
    description { Faker::Lorem.sentence }
    channel_type { "client" }
    configuration { {} }
    enabled { true }
    default { false }

    after(:build) do |channel|
      if channel.operation.blank? && channel.tenant.present?
        channel.operation = if channel.tenant&.id.present? && Tenant.exists?(channel.tenant.id)
                              channel.tenant.operations.order(created_at: :desc).first ||
                                channel.tenant.ensure_core_resources!.default_operation
                            else
                              build(:operation, tenant: channel.tenant)
                            end
      end

      channel.tenant = channel.operation&.tenant if channel.operation.present?
    end

    trait :client do
      channel_type { "client" }
    end

    trait :api do
      channel_type { "api" }
    end
  end

  factory :channel_target do
    channel
    target { association(:agent, operation: channel.operation) }
    configuration { {} }
    default { false }
    position { 0 }

    trait :mission do
      channel { association(:channel, :api) }
      target { association(:mission, operation: channel.operation) }
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
