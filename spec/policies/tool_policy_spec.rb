# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolPolicy do
  subject(:policy) { described_class.new(user, tool) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:tool) { build(:tool, operation: build(:operation, tenant:)) }

  context "when the user is a tenant admin managing a same-tenant tool" do
    let(:user) { build(:user, :admin, tenant:) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.new?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.edit?).to be(true) }
    it { expect(policy.destroy?).to be(true) }
    it { expect(policy.toggle?).to be(true) }
    it { expect(policy.discover_schema?).to be(true) }
    it { expect(policy.edit_visibility?).to be(true) }
    it { expect(policy.update_visibility?).to be(true) }
  end

  context "when the tool belongs to Headquarter" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:tool) { build(:tool, operation: build(:operation, :headquarter, tenant:)) }

    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.toggle?).to be(false) }
    it { expect(policy.discover_schema?).to be(false) }
    it { expect(policy.edit_visibility?).to be(false) }
    it { expect(policy.update_visibility?).to be(false) }
  end

  context "when the user is a tenant admin targeting another tenant's tool" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:tool) { build(:tool, operation: build(:operation, tenant: other_tenant)) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.toggle?).to be(false) }
    it { expect(policy.discover_schema?).to be(false) }
    it { expect(policy.edit_visibility?).to be(false) }
    it { expect(policy.update_visibility?).to be(false) }
  end

  context "when the user is not an admin" do
    let(:user) { build(:user, tenant:) }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.toggle?).to be(false) }
    it { expect(policy.discover_schema?).to be(false) }
    it { expect(policy.edit_visibility?).to be(false) }
    it { expect(policy.update_visibility?).to be(false) }
  end
end
