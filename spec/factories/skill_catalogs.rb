# frozen_string_literal: true

# == Schema Information
#
# Table name: skill_catalogs
# Database name: primary
#
#  id              :bigint           not null, primary key
#  description     :text
#  name            :string           not null
#  slug            :string           not null
#  source_metadata :jsonb            not null
#  source_type     :string           default("manual"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  operation_id    :bigint           not null
#
# Indexes
#
#  index_skill_catalogs_on_operation_id           (operation_id)
#  index_skill_catalogs_on_operation_id_and_name  (operation_id,name) UNIQUE
#  index_skill_catalogs_on_slug                   (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
FactoryBot.define do
  factory :skill_catalog do
    operation { OperationFactoryHelper.default_operation }
    sequence(:name) { |n| "Skill Catalog #{n}" }
    description { Faker::Lorem.sentence(word_count: 14) }
    source_type { "manual" }
    source_metadata { {} }

    trait :builtin do
      source_type { "builtin" }
      sequence(:source_metadata) { |n| { "builtin_key" => "builtin-catalog-#{n}" } }
    end
  end
end
