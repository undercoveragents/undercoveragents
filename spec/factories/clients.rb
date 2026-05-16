# frozen_string_literal: true

# == Schema Information
#
# Table name: clients
# Database name: primary
#
#  id            :bigint           not null, primary key
#  configuration :jsonb            not null
#  default       :boolean          default(FALSE), not null
#  name          :string           not null
#  slug          :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  agent_id      :bigint           not null
#  tenant_id     :bigint           not null
#
# Indexes
#
#  index_clients_on_agent_id            (agent_id)
#  index_clients_on_default             (default)
#  index_clients_on_slug                (slug) UNIQUE
#  index_clients_on_tenant_id           (tenant_id)
#  index_clients_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (agent_id => agents.id)
#  fk_rails_...  (tenant_id => tenants.id)
#
FactoryBot.define do
  factory :client do
    agent
    tenant { agent.operation.tenant }
    name { Faker::Company.unique.name }
    title { "<p><strong>#{Faker::Company.catch_phrase}</strong></p>" }
    welcome_message { "<p>#{Faker::Lorem.paragraph}</p>" }
    footer { "<p>#{Faker::Company.bs.capitalize}</p>" }
    default { true }

    trait :non_default do
      default { false }
    end

    trait :with_logo do
      after(:build) do |client|
        client.logo.attach(
          io: StringIO.new("fake-image-data"),
          filename: "logo.png",
          content_type: "image/png",
        )
      end
    end
  end
end
