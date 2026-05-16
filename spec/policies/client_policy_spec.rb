# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClientPolicy do
  subject(:policy) { described_class.new(user, client) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:same_tenant_llm_connector) { create(:connector, :llm_provider, :enabled, tenant:) }
  let(:other_tenant_llm_connector) { create(:connector, :llm_provider, :enabled, tenant: other_tenant) }
  let(:same_tenant_operation) { create(:operation, tenant:) }
  let(:same_tenant_agent) { create(:agent, operation: same_tenant_operation, llm_connector: same_tenant_llm_connector) }

  context "when the user is a tenant admin managing same-tenant clients" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:other_client) { create(:client, :non_default, agent: same_tenant_agent) }
    let(:client) { create(:client, agent: same_tenant_agent) }

    before { other_client }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.destroy?).to be(true) }
  end

  context "when the client is the last one in its tenant" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:client) { create(:client, agent: same_tenant_agent) }

    it { expect(policy.destroy?).to be(false) }
  end

  context "when the client record has no tenant yet" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:client) { Struct.new(:tenant_id, :id).new(nil, nil) }

    it { expect(policy.destroy?).to be(false) }

    it "returns false from the tenant existence helper" do
      expect(policy.send(:other_clients_exist_in_tenant?)).to be(false)
    end
  end

  context "when the user is a tenant admin targeting another tenant's client" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:other_agent) do
      create(
        :agent,
        operation: create(:operation, tenant: other_tenant),
        llm_connector: other_tenant_llm_connector,
      )
    end
    let(:client) { create(:client, agent: other_agent) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
  end

  context "when the user is not an admin" do
    let(:user) { build(:user, tenant:) }
    let(:client) { create(:client, agent: same_tenant_agent) }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
  end
end
