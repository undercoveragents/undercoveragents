# frozen_string_literal: true

# == Schema Information
#
# Table name: skill_resources
# Database name: primary
#
#  id            :bigint           not null, primary key
#  relative_path :string           not null
#  resource_kind :string           default("other"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  skill_id      :bigint           not null
#
# Indexes
#
#  index_skill_resources_on_skill_id                    (skill_id)
#  index_skill_resources_on_skill_id_and_relative_path  (skill_id,relative_path) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (skill_id => skills.id)
#
FactoryBot.define do
  factory :skill_resource do
    skill
    relative_path { "references/REFERENCE.md" }
    resource_kind { "references" }

    after(:build) do |resource|
      next if resource.file.attached?

      resource.file.attach(
        io: StringIO.new("Reference content"),
        filename: "REFERENCE.md",
        content_type: "text/markdown",
      )
    end
  end
end
