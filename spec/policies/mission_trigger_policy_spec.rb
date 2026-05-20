# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionTriggerPolicy do
  subject(:policy) { described_class.new(user, mission_trigger) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:mission_trigger) { build(:mission_trigger, mission: build(:mission, operation: build(:operation, tenant:))) }

  context "when the user is a tenant admin managing a same-tenant trigger" do
    let(:user) { build(:user, :admin, tenant:) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.destroy?).to be(true) }
    it { expect(policy.regenerate_secret?).to be(true) }
  end

  context "when the trigger belongs to Headquarter" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:mission_trigger) do
      build(:mission_trigger, mission: build(:mission, operation: build(:operation, :headquarter, tenant:)))
    end

    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.regenerate_secret?).to be(false) }
  end

  context "when the user targets another tenant's trigger" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:mission_trigger) do
      build(:mission_trigger, mission: build(:mission, operation: build(:operation, tenant: other_tenant)))
    end

    it { expect(policy.index?).to be(false) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.regenerate_secret?).to be(false) }
  end

  context "when the user is not an admin" do
    let(:user) { build(:user, tenant:) }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.regenerate_secret?).to be(false) }
  end
end
