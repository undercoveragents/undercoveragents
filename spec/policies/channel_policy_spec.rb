# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelPolicy do
  subject(:policy) { described_class.new(user, channel) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:channel) { build(:channel, tenant:) }

  context "when user is an admin in the same tenant" do
    let(:user) { build(:user, :admin, tenant:) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.destroy?).to be(true) }
    it { expect(policy.toggle?).to be(true) }
    it { expect(policy.regenerate_token?).to be(true) }
  end

  context "when user is an admin targeting another tenant's channel" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:channel) { build(:channel, tenant: other_tenant) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.toggle?).to be(false) }
    it { expect(policy.regenerate_token?).to be(false) }
  end

  context "when user is a regular user" do
    let(:user) { build(:user, tenant:) }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.toggle?).to be(false) }
    it { expect(policy.regenerate_token?).to be(false) }
  end

  context "when user is nil" do
    let(:user) { nil }

    it { expect(policy).not_to be_index }
    it { expect(policy).not_to be_show }
    it { expect(policy).not_to be_create }
    it { expect(policy).not_to be_update }
    it { expect(policy).not_to be_destroy }
    it { expect(policy).not_to be_toggle }
    it { expect(policy).not_to be_regenerate_token }
  end
end
