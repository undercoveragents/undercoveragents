# frozen_string_literal: true

require "rails_helper"

RSpec.describe RagFlowPolicy do
  subject(:policy) { described_class.new(user, rag_flow) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:rag_flow) { build(:rag_flow, operation: build(:operation, tenant:)) }

  context "when the user is a tenant admin managing a same-tenant flow" do
    let(:user) { build(:user, :admin, tenant:) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(true) }
    it { expect(policy.update?).to be(true) }
    it { expect(policy.destroy?).to be(true) }
    it { expect(policy.toggle?).to be(true) }

    describe "#execute?" do
      it "is true when enabled and runnable" do
        allow(rag_flow).to receive(:runnable?).and_return(true)

        expect(policy.execute?).to be(true)
      end

      it "is false when disabled" do
        rag_flow.enabled = false
        allow(rag_flow).to receive(:runnable?).and_return(true)

        expect(policy.execute?).to be(false)
      end

      it "is false when not runnable" do
        allow(rag_flow).to receive(:runnable?).and_return(false)

        expect(policy.execute?).to be(false)
      end
    end
  end

  context "when the flow belongs to Headquarter" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:rag_flow) { build(:rag_flow, operation: build(:operation, :headquarter, tenant:)) }

    it { expect(policy.show?).to be(true) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.toggle?).to be(false) }
    it { expect(policy.execute?).to be(false) }
  end

  context "when the user is a tenant admin targeting another tenant's flow" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:rag_flow) { build(:rag_flow, operation: build(:operation, tenant: other_tenant)) }

    it { expect(policy.index?).to be(true) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.toggle?).to be(false) }
    it { expect(policy.execute?).to be(false) }
  end

  context "when the user is not an admin" do
    let(:user) { build(:user, tenant:) }

    it { expect(policy.index?).to be(false) }
    it { expect(policy.show?).to be(false) }
    it { expect(policy.create?).to be(false) }
    it { expect(policy.update?).to be(false) }
    it { expect(policy.destroy?).to be(false) }
    it { expect(policy.toggle?).to be(false) }
    it { expect(policy.execute?).to be(false) }
  end
end
