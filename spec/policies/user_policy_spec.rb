# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserPolicy do
  subject(:policy) { described_class.new(user, record) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:record) { build(:user, tenant:) }

  context "when user is a tenant admin managing a user in the same tenant" do
    let(:user) { build(:user, :admin, tenant:) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.destroy?).to be(true) }
  end

  context "when a tenant admin targets a system admin record" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:record) { build(:user, :system_admin, tenant:) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
  end

  context "when a tenant admin targets another tenant's user" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:record) { build(:user, tenant: other_tenant) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
  end

  context "when user is a system admin in the same tenant" do
    let(:user) { build(:user, :system_admin, tenant:) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.destroy?).to be(true) }
  end

  context "when user is a system admin targeting another tenant's user" do
    let(:user) { build(:user, :system_admin, tenant: other_tenant) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
  end

  context "when user is regular user" do
    let(:user) { build(:user, role: "user", tenant:) }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
  end

  context "when user is nil" do
    let(:user) { nil }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
  end
end
