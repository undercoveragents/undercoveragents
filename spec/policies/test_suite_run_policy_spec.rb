# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuiteRunPolicy do
  subject(:policy) { described_class.new(user, run) }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }

  describe "show" do
    let(:user) { build(:user, :admin, tenant:) }
    let(:run) do
      build(
        :test_suite_run,
        test_suite: build(:test_suite, agent: build(:agent, operation: build(:operation, tenant:))),
      )
    end

    it { expect(policy.show?).to be(true) }

    it "denies access to runs from other tenants" do
      foreign_run = build(
        :test_suite_run,
        test_suite: build(:test_suite, agent: build(:agent, operation: build(:operation, tenant: other_tenant))),
      )

      expect(described_class.new(user, foreign_run).show?).to be(false)
    end
  end

  describe "cancel" do
    let(:user) { build(:user, :admin, tenant:) }

    context "when run is in progress" do
      let(:run) do
        build(
          :test_suite_run,
          :running,
          test_suite: build(:test_suite, agent: build(:agent, operation: build(:operation, tenant:))),
        )
      end

      it { expect(policy.cancel?).to be(true) }
    end

    context "when run is completed" do
      let(:run) do
        build(
          :test_suite_run,
          :completed,
          test_suite: build(:test_suite, agent: build(:agent, operation: build(:operation, tenant:))),
        )
      end

      it { expect(policy.cancel?).to be(false) }
    end

    context "when run is failed" do
      let(:run) do
        build(
          :test_suite_run,
          status: :failed,
          test_suite: build(:test_suite, agent: build(:agent, operation: build(:operation, tenant:))),
        )
      end

      it { expect(policy.cancel?).to be(false) }
    end

    context "when run is cancelled" do
      let(:run) do
        build(
          :test_suite_run,
          status: :cancelled,
          test_suite: build(:test_suite, agent: build(:agent, operation: build(:operation, tenant:))),
        )
      end

      it { expect(policy.cancel?).to be(false) }
    end

    context "when the run belongs to another tenant" do
      let(:run) do
        build(
          :test_suite_run,
          :running,
          test_suite: build(:test_suite, agent: build(:agent, operation: build(:operation, tenant: other_tenant))),
        )
      end

      it { expect(policy.cancel?).to be(false) }
    end

    context "when the user is not an admin" do
      let(:user) { build(:user, tenant:) }
      let(:run) do
        build(
          :test_suite_run,
          :running,
          test_suite: build(:test_suite, agent: build(:agent, operation: build(:operation, tenant:))),
        )
      end

      it { expect(policy.show?).to be(false) }
      it { expect(policy.cancel?).to be(false) }
    end
  end
end
