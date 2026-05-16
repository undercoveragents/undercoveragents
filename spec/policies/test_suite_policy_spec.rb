# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuitePolicy do
  subject(:policy) { described_class.new(user, test_suite) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:test_suite) { build(:test_suite, agent: build(:agent, operation: build(:operation, tenant:))) }

  context "when the user is a tenant admin managing a same-tenant suite" do
    let(:user) { build(:user, :admin, tenant:) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.destroy?).to be(true) }
    it { expect(policy.run?).to be(true) }
  end

  context "when the user is a tenant admin targeting another tenant's suite" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:test_suite) { build(:test_suite, agent: build(:agent, operation: build(:operation, tenant: other_tenant))) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.run?).to be(false) }
  end

  context "when the user is not an admin" do
    let(:user) { build(:user, tenant:) }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.run?).to be(false) }
  end
end
