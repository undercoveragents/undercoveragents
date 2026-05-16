# frozen_string_literal: true

# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  email               :string           not null
#  password_digest     :string
#  provider            :string
#  role                :string           default("user"), not null
#  status              :string           default("active"), not null
#  telegram_link_token :string
#  telegram_username   :string
#  uid                 :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  telegram_user_id    :bigint
#  tenant_id           :bigint           not null
#
# Indexes
#
#  index_users_on_email                (email) UNIQUE
#  index_users_on_provider_and_uid     (provider,uid) UNIQUE WHERE (provider IS NOT NULL)
#  index_users_on_role                 (role)
#  index_users_on_telegram_link_token  (telegram_link_token) UNIQUE WHERE (telegram_link_token IS NOT NULL)
#  index_users_on_telegram_user_id     (telegram_user_id) UNIQUE WHERE (telegram_user_id IS NOT NULL)
#  index_users_on_tenant_id            (tenant_id)
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id)
#
FactoryBot.define do
  factory :user do
    tenant { Tenant.order(:id).first || association(:tenant) }
    email { Faker::Internet.unique.email }
    password { "Password123!" }
    role { "user" }
    status { "active" }

    trait :admin do
      role { "admin" }
    end

    trait :system_admin do
      role { "system_admin" }
    end

    trait :inactive do
      status { "inactive" }
    end

    trait :oauth do
      provider { "keycloak_openid" }
      uid { SecureRandom.uuid }
      password { nil }
    end
  end
end
