# frozen_string_literal: true

# == Schema Information
#
# Table name: models
# Database name: primary
#
#  id                :bigint           not null, primary key
#  capabilities      :jsonb
#  context_window    :integer
#  family            :string
#  knowledge_cutoff  :date
#  max_output_tokens :integer
#  metadata          :jsonb
#  modalities        :jsonb
#  model_created_at  :datetime
#  name              :string           not null
#  pricing           :jsonb
#  provider          :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  model_id          :string           not null
#
# Indexes
#
#  index_models_on_capabilities           (capabilities) USING gin
#  index_models_on_family                 (family)
#  index_models_on_modalities             (modalities) USING gin
#  index_models_on_provider               (provider)
#  index_models_on_provider_and_model_id  (provider,model_id) UNIQUE
#
FactoryBot.define do
  factory :model do
    sequence(:model_id) { |n| "gpt-#{n}" }
    name { Faker::Lorem.words(number: 2).join(" ").titleize }
    provider { "openai" }
    context_window { 128_000 }
    max_output_tokens { 4096 }
    family { "gpt" }
    capabilities { ["text"] }
    modalities { { "input" => ["text"], "output" => ["text"] } }
    pricing do
      {
        "text_tokens" => {
          "standard" => {
            "input_per_million" => "3.00",
            "output_per_million" => "15.00",
            "cached_input_per_million" => "1.50",
            "cache_creation_per_million" => "3.75",
          },
        },
      }
    end
    metadata { {} }
  end
end
