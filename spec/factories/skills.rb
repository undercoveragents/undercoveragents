# frozen_string_literal: true

# == Schema Information
#
# Table name: skills
# Database name: primary
#
#  id               :bigint           not null, primary key
#  allowed_tools    :string
#  compatibility    :string
#  description      :text             not null
#  instructions     :text
#  license          :string
#  metadata         :jsonb            not null
#  name             :string           not null
#  source_metadata  :jsonb            not null
#  source_type      :string           default("manual"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  skill_catalog_id :bigint           not null
#
# Indexes
#
#  index_skills_on_skill_catalog_id           (skill_catalog_id)
#  index_skills_on_skill_catalog_id_and_name  (skill_catalog_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (skill_catalog_id => skill_catalogs.id)
#
FactoryBot.define do
  factory :skill do
    skill_catalog
    sequence(:name) { |n| "skill-#{n}" }
    description { "Use this skill when the user needs a repeatable workflow with clear steps and references." }
    instructions { "# Use this skill\n\n1. Read the task carefully.\n2. Follow the steps.\n" }
    source_type { "manual" }
    metadata { {} }
    source_metadata { {} }

    trait :imported do
      source_type { "imported" }
      source_metadata { { "warnings" => ["The imported directory name does not match the skill name frontmatter."] } }
    end

    trait :builtin do
      source_type { "builtin" }
      sequence(:source_metadata) { |n| { "builtin_key" => "builtin-skill-#{n}" } }
    end
  end
end
