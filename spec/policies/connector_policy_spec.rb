# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConnectorPolicy do
  subject(:policy) { described_class.new(user, record) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }

  context "when the user is a tenant admin managing same-tenant connectors" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:record) { build(:connector, tenant:) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.destroy?).to be(true) }
    it { expect(policy.toggle?).to be(true) }
    it { expect(policy.fetch_bot_info?).to be(true) }
    it { expect(policy.setup_webhook?).to be(true) }
    it { expect(policy.transport_fields?).to be(true) }
    it { expect(policy.provider_fields?).to be(true) }
  end

  context "when the user is a tenant admin targeting another tenant's connector" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:record) { build(:connector, tenant: other_tenant) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.toggle?).to be(false) }
    it { expect(policy.fetch_bot_info?).to be(false) }
    it { expect(policy.setup_webhook?).to be(false) }
    it { expect(policy.transport_fields?).to be(false) }
    it { expect(policy.provider_fields?).to be(false) }
  end

  context "when a class-level connector action is authorized" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:record) { Connector }

    around do |example|
      Current.set(tenant:) { example.run }
    end

    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.provider_fields?).to be(true) }
    it { expect(policy.transport_fields?).to be(true) }
  end

  context "when the user is not an admin" do
    let(:user) { build(:user, tenant:) }
    let(:record) { build(:connector, tenant:) }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.toggle?).to be(false) }
    it { expect(policy.fetch_bot_info?).to be(false) }
    it { expect(policy.setup_webhook?).to be(false) }
    it { expect(policy.transport_fields?).to be(false) }
    it { expect(policy.provider_fields?).to be(false) }
  end
end
