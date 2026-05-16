# frozen_string_literal: true

require "rails_helper"

RSpec.describe SkillPolicy do
  subject(:policy) { described_class.new(user, skill) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:skill) { build(:skill, skill_catalog: build(:skill_catalog, operation: build(:operation, tenant:))) }

  context "when the user is a tenant admin managing a same-tenant skill" do
    let(:user) { build(:user, :admin, tenant:) }

    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.destroy?).to be(true) }
  end

  context "when the skill belongs to Headquarter" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:skill) do
      build(:skill, skill_catalog: build(:skill_catalog, operation: build(:operation, :headquarter, tenant:)))
    end

    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.restore?).to be(false) }
    it { expect(policy.destroy?).to be(false) }

    it "allows restoring builtin skills in Headquarter" do
      builtin_catalog = build(
        :skill_catalog,
        :builtin,
        operation: build(:operation, :headquarter, tenant:),
      )
      builtin_skill = build(:skill, :builtin, skill_catalog: builtin_catalog)

      expect(described_class.new(user, builtin_skill).restore?).to be(true)
    end
  end

  context "when the user is a tenant admin targeting another tenant's skill" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:skill) do
      build(:skill, skill_catalog: build(:skill_catalog, operation: build(:operation, tenant: other_tenant)))
    end

    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
  end

  context "when the user is not an admin" do
    let(:user) { build(:user, tenant:) }

    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
  end
end
