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
require "rails_helper"

RSpec.describe User do
  subject(:user) { build(:user) }

  # ── Validations ──────────────────────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to validate_presence_of(:role) }
    it { is_expected.to validate_presence_of(:status) }

    context "when local account" do
      subject(:user) { build(:user, provider: nil) }

      it { is_expected.to validate_presence_of(:password) }
      it { is_expected.to validate_length_of(:password).is_at_least(8) }
    end

    context "when oauth account" do
      subject(:user) { build(:user, :oauth) }

      it { is_expected.not_to validate_presence_of(:password) }
    end

    context "with invalid email format" do
      it "is invalid" do
        user.email = "not-an-email"
        expect(user).not_to be_valid
        expect(user.errors[:email]).to be_present
      end
    end
  end

  # ── Enums ────────────────────────────────────────────────────────────────────
  describe "enums" do
    it do
      expect(user).to define_enum_for(:role)
        .backed_by_column_of_type(:string)
        .with_values(user: "user", admin: "admin", system_admin: "system_admin")
    end

    it do
      expect(user).to define_enum_for(:status)
        .backed_by_column_of_type(:string)
        .with_values(active: "active", inactive: "inactive")
    end
  end

  # ── Scopes ───────────────────────────────────────────────────────────────────
  describe ".ordered" do
    it "orders by email" do
      z_account = create(:user, email: "z@test.com")
      a_account = create(:user, email: "a@test.com")

      expect(described_class.ordered).to eq([a_account, z_account])
    end
  end

  describe ".local_accounts" do
    it "returns only local accounts" do
      local = create(:user, provider: nil)
      create(:user, :oauth)

      expect(described_class.local_accounts).to eq([local])
    end
  end

  describe ".oauth_accounts" do
    it "returns only oauth accounts" do
      create(:user, provider: nil)
      oauth = create(:user, :oauth)

      expect(described_class.oauth_accounts).to eq([oauth])
    end
  end

  # ── Instance Methods ─────────────────────────────────────────────────────────
  describe "#local?" do
    it "returns true when provider is blank" do
      expect(build(:user, provider: nil)).to be_local
    end

    it "returns false when provider is present" do
      expect(build(:user, :oauth)).not_to be_local
    end
  end

  describe "#oauth?" do
    it "returns true when provider is present" do
      expect(build(:user, :oauth)).to be_oauth
    end

    it "returns false when provider is blank" do
      expect(build(:user, provider: nil)).not_to be_oauth
    end
  end

  describe "#display_name" do
    it "extracts name from email" do
      user = build(:user, email: "john@example.com")
      expect(user.display_name).to eq("John")
    end
  end

  describe "#initials" do
    it "returns the first letter of display name" do
      user = build(:user, email: "john@example.com")
      expect(user.initials).to eq("J")
    end
  end

  describe "tenant access helpers" do
    let(:tenant) { create(:tenant) }

    it "allows system admins to access and manage any tenant" do
      user = build(:user, :system_admin)

      expect(user.can_access_tenant?(tenant)).to be(true)
      expect(user.can_manage_tenant?(tenant)).to be(true)
    end

    it "allows tenant admins to manage only their own tenant" do
      user = build(:user, :admin, tenant:)

      expect(user.can_access_tenant?(tenant)).to be(true)
      expect(user.can_manage_tenant?(tenant)).to be(true)
      expect(user.can_access_tenant?(create(:tenant))).to be(false)
      expect(user.can_manage_tenant?(create(:tenant))).to be(false)
    end

    it "returns false when the tenant is blank" do
      user = build(:user, :admin)

      expect(user.can_access_tenant?(nil)).to be(false)
      expect(user.can_manage_tenant?(nil)).to be(false)
    end
  end

  describe "#authenticate" do
    it "returns the account for valid password" do
      user = create(:user, password: "Validpass1!")
      expect(user.authenticate("Validpass1!")).to eq(user)
    end

    it "returns false for invalid password" do
      user = create(:user, password: "Validpass1!")
      expect(user.authenticate("wrongpassword")).to be(false)
    end
  end

  # ── Password for existing records ──────────────────────────────────────────
  describe "password updates" do
    it "allows updating without changing password" do
      user = create(:user)
      user.email = "newemail@test.com"

      expect(user).to be_valid
    end

    it "validates password length when changing password" do
      user = create(:user)
      user.password = "short"

      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end
  end

  # ── Password Complexity ──────────────────────────────────────────────────────
  describe "password complexity" do
    it "requires at least one uppercase letter" do
      user = build(:user, password: "lowercase1!")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("must include at least one uppercase letter")
    end

    it "requires at least one lowercase letter" do
      user = build(:user, password: "UPPERCASE1!")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("must include at least one lowercase letter")
    end

    it "requires at least one digit" do
      user = build(:user, password: "NoDigits!!")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("must include at least one digit")
    end

    it "requires at least one special character" do
      user = build(:user, password: "NoSpecial1")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("must include at least one special character")
    end

    it "accepts a fully compliant password" do
      user = build(:user, password: "Secure1!")
      expect(user).to be_valid
    end
  end

  # ── Password Reset Token (built-in) ────────────────────────────────────────
  describe "#password_reset_token" do
    it "generates a signed token" do
      user = create(:user)
      token = user.password_reset_token

      expect(token).to be_present
    end

    it "generates a token for an OAuth user (no password_salt)" do
      user = create(:user, :oauth)
      token = user.password_reset_token

      expect(token).to be_present
    end

    it "can find account by valid token" do
      user = create(:user)
      token = user.password_reset_token

      found = described_class.find_by_token_for(:password_reset, token)
      expect(found).to eq(user)
    end

    it "returns nil for invalid token" do
      found = described_class.find_by_token_for(:password_reset, "invalid")
      expect(found).to be_nil
    end

    it "invalidates token after password change" do
      user = create(:user)
      token = user.password_reset_token

      user.update!(password: "NewPass123!")

      found = described_class.find_by_token_for(:password_reset, token)
      expect(found).to be_nil
    end
  end
end
