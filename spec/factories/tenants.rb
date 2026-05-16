# frozen_string_literal: true

# == Schema Information
#
# Table name: tenants
# Database name: primary
#
#  id          :bigint           not null, primary key
#  description :text
#  name        :string           not null
#  slug        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_tenants_on_name  (name) UNIQUE
#  index_tenants_on_slug  (slug) UNIQUE
#
FactoryBot.define do
  factory :tenant do
    sequence(:name) { |n| "Tenant #{n}" }
    description { Faker::Company.catch_phrase }
  end
end
