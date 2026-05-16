# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentPolicy do
  subject(:policy) { described_class.new(user, agent) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:agent) { build(:agent, operation: build(:operation, tenant:)) }

  context "when the user is a tenant admin managing a same-tenant agent" do
    let(:user) { build(:user, :admin, tenant:) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.new?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.edit?).to be(true) }
    it { expect(policy.destroy?).to be(true) }
    it { expect(policy.toggle?).to be(true) }
    it { expect(policy.restore_defaults?).to be(false) }

    it "forbids destroying builtin agents" do
      builtin_agent = build(:agent, builtin: true, builtin_key: "code_assistant", operation: build(:operation, tenant:))

      expect(described_class.new(user, builtin_agent).destroy?).to be(false)
    end

    it "allows restoring builtin agents" do
      builtin_agent = build(:agent, builtin: true, builtin_key: "code_assistant", operation: build(:operation, tenant:))

      expect(described_class.new(user, builtin_agent).restore?).to be(true)
    end

    it "allows restore authorization for same-tenant agents" do
      expect(policy.restore?).to be(true)
    end
  end

  context "when the agent belongs to Headquarter" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:headquarter) { build(:operation, :headquarter, tenant:) }
    let(:agent) { build(:agent, operation: headquarter) }

    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.toggle?).to be(false) }
    it { expect(policy.restore?).to be(false) }
    it { expect(policy.restore_defaults?).to be(false) }

    it "uses the shared read-only reason" do
      expect(policy.denied_reason(:update?)).to eq(ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE)
    end

    it "allows restoring builtin agents in Headquarter" do
      builtin_agent = build(:agent, builtin: true, builtin_key: "code_assistant", operation: headquarter)

      expect(described_class.new(user, builtin_agent).restore?).to be(true)
    end
  end

  context "when creating from Headquarter context" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:headquarter) { create(:operation, :headquarter, tenant:) }

    it "denies create on class policies" do
      Current.set(operation: headquarter) do
        expect(described_class.new(user, Agent).create?).to be(false)
      end
    end

    it "allows restore defaults on class policies" do
      Current.set(operation: headquarter) do
        expect(described_class.new(user, Agent).restore_defaults?).to be(true)
      end
    end
  end

  context "when the user is a tenant admin targeting another tenant's agent" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:agent) { build(:agent, operation: build(:operation, tenant: other_tenant)) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.toggle?).to be(false) }
    it { expect(policy.restore?).to be(false) }
    it { expect(policy.restore_defaults?).to be(false) }
  end

  context "when the user is not an admin" do
    let(:user) { build(:user, tenant:) }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.toggle?).to be(false) }
    it { expect(policy.restore?).to be(false) }
    it { expect(policy.restore_defaults?).to be(false) }
  end
end
