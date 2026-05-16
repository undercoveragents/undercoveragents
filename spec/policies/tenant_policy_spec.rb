# frozen_string_literal: true

require "rails_helper"

RSpec.describe TenantPolicy do
  subject(:policy) { described_class.new(user, tenant) }

  let(:tenant) { build(:tenant) }

  context "when the user is a system admin" do
    let(:user) { build(:user, :system_admin) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.destroy?).to be(true) }
  end

  context "when the user is a tenant admin" do
    let(:user) { build(:user, :admin) }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
  end

  context "when the user is nil" do
    let(:user) { nil }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
  end
end
