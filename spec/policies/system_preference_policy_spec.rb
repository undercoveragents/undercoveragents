# frozen_string_literal: true

require "rails_helper"

RSpec.describe SystemPreferencePolicy do
  subject(:policy) { described_class.new(user, preference) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:preference) { build(:system_preference, tenant:) }

  context "when the user is a tenant admin managing same-tenant preferences" do
    let(:user) { build(:user, :admin, tenant:) }

    it { expect(policy.show?).to be(true) }
    it { expect(policy.update?).to be(true) }
  end

  context "when the user is a tenant admin targeting another tenant's preferences" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:preference) { build(:system_preference, tenant: other_tenant) }

    it { expect(policy.show?).to be(false) }
    it { expect(policy.update?).to be(false) }
  end

  context "when the user is not an admin" do
    let(:user) { build(:user, tenant:) }

    it { expect(policy.show?).to be(false) }
    it { expect(policy.update?).to be(false) }
  end
end
