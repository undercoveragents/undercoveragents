# frozen_string_literal: true

require "rails_helper"

RSpec.describe OperationPolicy do
  subject(:policy) { described_class.new(user, operation) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:operation) { build(:operation, tenant:) }

  context "when the user is a tenant admin managing a same-tenant operation" do
    let(:user) { build(:user, :admin, tenant:) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.new?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.edit?).to be(true) }
    it { expect(policy.switch?).to be(true) }

    it "allows destroying destroyable operations" do
      expect(policy.destroy?).to be(true)
    end

    it "still authorizes protected operations and leaves the delete guard to the controller" do
      allow(operation).to receive(:destroyable?).and_return(false)

      expect(policy.destroy?).to be(true)
    end
  end

  context "when the operation is Headquarter" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:operation) { build(:operation, :headquarter, tenant:) }

    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.switch?).to be(true) }

    it "uses the shared read-only reason for updates" do
      expect(policy.denied_reason(:update?)).to eq(ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE)
    end
  end

  context "when the user is a tenant admin targeting another tenant's operation" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:operation) { build(:operation, tenant: other_tenant) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.switch?).to be(false) }
  end

  context "when the user is not an admin" do
    let(:user) { build(:user, tenant:) }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.switch?).to be(false) }
  end
end
