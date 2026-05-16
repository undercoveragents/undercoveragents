# frozen_string_literal: true

require "rails_helper"

RSpec.describe SkillCatalogPolicy do
  subject(:policy) { described_class.new(user, skill_catalog) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:skill_catalog) { build(:skill_catalog, operation: build(:operation, tenant:)) }

  context "when the user is a tenant admin managing a same-tenant skill catalog" do
    let(:user) { build(:user, :admin, tenant:) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.restore_defaults?).to be(false) }
    it { expect(policy.destroy?).to be(true) }
    it { expect(policy.import?).to be(true) }
    it { expect(policy.create_import?).to be(true) }
    it { expect(policy.attach_agent?).to be(true) }
    it { expect(policy.detach_agent?).to be(true) }
  end

  context "when the skill catalog belongs to Headquarter" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:skill_catalog) { build(:skill_catalog, operation: build(:operation, :headquarter, tenant:)) }

    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.restore?).to be(false) }
    it { expect(policy.restore_defaults?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.import?).to be(false) }
    it { expect(policy.create_import?).to be(false) }
    it { expect(policy.attach_agent?).to be(false) }
    it { expect(policy.detach_agent?).to be(false) }

    it "allows restoring builtin skill catalogs in Headquarter" do
      builtin_catalog = build(:skill_catalog, :builtin, operation: build(:operation, :headquarter, tenant:))

      expect(described_class.new(user, builtin_catalog).restore?).to be(true)
    end
  end

  context "when restoring defaults from Headquarter context" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:headquarter) { create(:operation, :headquarter, tenant:) }

    it "allows restore defaults on class policies" do
      Current.set(operation: headquarter) do
        expect(described_class.new(user, SkillCatalog).restore_defaults?).to be(true)
      end
    end
  end

  context "when the user is a tenant admin targeting another tenant's skill catalog" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:skill_catalog) { build(:skill_catalog, operation: build(:operation, tenant: other_tenant)) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.import?).to be(false) }
    it { expect(policy.create_import?).to be(false) }
    it { expect(policy.attach_agent?).to be(false) }
    it { expect(policy.detach_agent?).to be(false) }
  end

  context "when the user is not an admin" do
    let(:user) { build(:user, tenant:) }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.import?).to be(false) }
    it { expect(policy.create_import?).to be(false) }
    it { expect(policy.attach_agent?).to be(false) }
    it { expect(policy.detach_agent?).to be(false) }
  end
end
