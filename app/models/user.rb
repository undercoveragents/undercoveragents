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
class User < ApplicationRecord
  has_secure_password validations: false

  # Override built-in password reset token expiry (default 15 minutes)
  generates_token_for :password_reset, expires_in: 2.hours do
    password_salt&.last(10)
  end

  # ── Enums ──────────────────────────────────────────────────────────────────────
  enum :role, { user: "user", admin: "admin", system_admin: "system_admin" }
  enum :status, { active: "active", inactive: "inactive" }

  # ── Associations ──────────────────────────────────────────────────────────────
  belongs_to :tenant
  has_many :chats, dependent: :nullify
  # ── Scopes ─────────────────────────────────────────────────────────────────────
  scope :ordered, -> { order(:email) }
  scope :local_accounts, -> { where(provider: nil) }
  scope :oauth_accounts, -> { where.not(provider: nil) }
  scope :for_tenant, ->(tenant) { where(tenant:) }
  # ── Validations ────────────────────────────────────────────────────────────────
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true,
                       length: { minimum: 8 },
                       password_complexity: true,
                       confirmation: true,
                       if: :password_required?
  validates :role, presence: true
  validates :status, presence: true

  # ── Instance Methods ───────────────────────────────────────────────────────────
  def local?
    provider.blank?
  end

  def oauth?
    provider.present?
  end

  def tenant_admin?
    role == "admin"
  end

  def admin?
    tenant_admin? || system_admin?
  end

  def can_access_tenant?(tenant)
    tenant.present? && (system_admin? || tenant_id == tenant.id)
  end

  def can_manage_tenant?(tenant)
    tenant.present? && (system_admin? || (tenant_admin? && tenant_id == tenant.id))
  end

  def display_name
    email.split("@").first.titleize
  end

  def initials
    display_name[0].upcase
  end

  private

  def password_required?
    provider.blank? && (new_record? || password.present?)
  end
end
