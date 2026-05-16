# frozen_string_literal: true

# == Schema Information
#
# Table name: operations
# Database name: primary
#
#  id          :bigint           not null, primary key
#  description :text
#  icon        :string           default("fa-solid fa-briefcase")
#  name        :string           not null
#  slug        :string           not null
#  system      :boolean          default(FALSE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  tenant_id   :bigint           not null
#
# Indexes
#
#  index_operations_on_slug                (slug) UNIQUE
#  index_operations_on_system              (system)
#  index_operations_on_tenant_id           (tenant_id)
#  index_operations_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id)
#
FactoryBot.define do
  factory :operation do
    tenant { Tenant.order(:id).first || association(:tenant) }
    name { Faker::Lorem.unique.words(number: 3).join(" ").titleize }
    description { Faker::Lorem.sentence }
    icon { "fa-solid fa-briefcase" }
    system { false }

    trait :system do
      system { true }
    end

    trait :headquarter do
      name { Operation::HEADQUARTER_NAME }
      icon { "fa-solid fa-building-shield" }
      system { true }
    end

    trait :default do
      name { Operation::DEFAULT_NAME }
      icon { "fa-solid fa-briefcase" }
      system { false }
    end
  end
end
