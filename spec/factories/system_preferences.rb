# frozen_string_literal: true

# == Schema Information
#
# Table name: system_preferences
# Database name: primary
#
#  id                     :bigint           not null, primary key
#  custom_llm_params      :jsonb            not null
#  temperature            :float
#  thinking_budget        :integer
#  thinking_effort        :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  embedding_connector_id :bigint
#  embedding_model_id     :string
#  image_connector_id     :bigint
#  image_model_id         :string
#  llm_connector_id       :bigint
#  model_id               :string
#  tenant_id              :bigint           not null
#
# Indexes
#
#  index_system_preferences_on_tenant_id  (tenant_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (embedding_connector_id => connectors.id)
#  fk_rails_...  (image_connector_id => connectors.id)
#  fk_rails_...  (llm_connector_id => connectors.id)
#  fk_rails_...  (tenant_id => tenants.id)
#
FactoryBot.define do
  factory :system_preference do
    tenant { Tenant.order(:id).first || association(:tenant) }

    trait :configured do
      llm_connector { association :connector, :llm_provider, :enabled, tenant: }
      model_id { "gpt-4.1" }
    end

    trait :with_embedding do
      embedding_connector { association :connector, :llm_provider, :enabled, tenant: }
      embedding_model_id { "text-embedding-3-small" }
    end

    trait :with_image do
      image_connector { association :connector, :llm_provider, :enabled, tenant: }
      image_model_id { "gpt-image-1" }
    end
  end
end
