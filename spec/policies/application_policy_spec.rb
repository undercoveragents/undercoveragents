# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationPolicy do
  subject(:policy) { described_class.new(nil, record) }

  let(:record) { double("Record") } # rubocop:disable RSpec/VerifiedDoubles

  let(:policy_class) do
    Class.new(described_class) do
      def create?
        admin_with_record_access?
      end

      def resolved_tenant_id(target)
        tenant_id_for(target)
      end

      def resolved_operation(target)
        operation_for(target)
      end

      def system_admin_user?
        system_admin?
      end
    end
  end

  describe "#index?" do
    it "permits index" do
      expect(policy.index?).to be(true)
    end
  end

  describe "#show?" do
    it "permits show" do
      expect(policy.show?).to be(true)
    end
  end

  describe "#denied_reason" do
    it "returns nil when the query is allowed" do
      expect(policy.denied_reason(:show?)).to be_nil
    end

    it "returns the generic message for denied non-headquarter actions" do
      expect(policy.denied_reason(:create?)).to eq("You do not have permission to do that.")
    end
  end

  describe "#create?" do
    it "denies create" do
      expect(policy.create?).to be(false)
    end
  end

  describe "#new?" do
    it "delegates to create?" do
      expect(policy.new?).to eq(policy.create?)
    end
  end

  describe "#update?" do
    it "denies update" do
      expect(policy.update?).to be(false)
    end
  end

  describe "#edit?" do
    it "delegates to update?" do
      expect(policy.edit?).to eq(policy.update?)
    end
  end

  describe "#destroy?" do
    it "denies destroy" do
      expect(policy.destroy?).to be(false)
    end
  end

  describe "#duplicate?" do
    it "denies duplicate" do
      expect(policy.duplicate?).to be(false)
    end
  end

  describe "tenant-aware helpers" do
    let(:tenant) { create(:tenant) }
    let(:admin) { create(:user, :admin, tenant:) }

    it "allows tenant admins to authorize class records within the current tenant context" do
      Current.set(tenant:) do
        expect(policy_class.new(admin, Connector).create?).to be(true)
      end
    end

    it "denies class-level authorization when no tenant context is available" do
      expect(policy_class.new(admin, Connector).create?).to be(false)
    end

    it "denies system admins access to foreign-tenant records" do
      foreign_record = build(:connector, tenant: create(:tenant))
      system_admin = create(:user, :system_admin, tenant: create(:tenant))

      expect(policy_class.new(system_admin, foreign_record).create?).to be(false)
    end

    it "allows system admins to authorize same-tenant records" do
      system_admin = create(:user, :system_admin, tenant:)
      same_tenant_record = build(:connector, tenant:)

      expect(policy_class.new(system_admin, same_tenant_record).create?).to be(true)
    end

    it "denies tenant admins access to foreign-tenant records" do
      foreign_record = build(:connector, tenant: create(:tenant))

      expect(policy_class.new(admin, foreign_record).create?).to be(false)
    end

    it "denies regular users even when tenant matches" do
      regular_user = create(:user, tenant:)
      same_tenant_record = build(:connector, tenant:)

      expect(policy_class.new(regular_user, same_tenant_record).create?).to be(false)
    end

    it "denies access when no user is present" do
      same_tenant_record = build(:connector, tenant:)

      expect(policy_class.new(nil, same_tenant_record).create?).to be(false)
    end

    it "resolves tenant ids from direct tenant_id ownership" do
      connector = build(:connector, tenant:)

      expect(policy_class.new(admin, connector).resolved_tenant_id(connector)).to eq(tenant.id)
    end

    it "resolves tenant ids from tenant associations" do
      record = Struct.new(:tenant).new(tenant)

      expect(policy_class.new(admin, record).resolved_tenant_id(record)).to eq(tenant.id)
    end

    it "returns nil for records with a blank tenant_id" do
      record = Struct.new(:tenant_id).new(nil)

      expect(policy_class.new(admin, record).resolved_tenant_id(record)).to be_nil
    end

    it "resolves tenant ids through operations" do
      agent = build(:agent, operation: build(:operation, tenant:))

      expect(policy_class.new(admin, agent).resolved_tenant_id(agent)).to eq(tenant.id)
    end

    it "resolves tenant ids through skill catalogs" do
      skill = build(:skill, skill_catalog: build(:skill_catalog, operation: build(:operation, tenant:)))

      expect(policy_class.new(admin, skill).resolved_tenant_id(skill)).to eq(tenant.id)
    end

    it "resolves tenant ids through agent-backed test suites" do
      test_suite = build(:test_suite, agent: build(:agent, operation: build(:operation, tenant:)))

      expect(policy_class.new(admin, test_suite).resolved_tenant_id(test_suite)).to eq(tenant.id)
    end

    it "resolves tenant ids through mission-backed test suites" do
      test_suite = build(:test_suite, :mission_suite, mission: build(:mission, operation: build(:operation, tenant:)))

      expect(policy_class.new(admin, test_suite).resolved_tenant_id(test_suite)).to eq(tenant.id)
    end

    it "resolves tenant ids through test suite runs" do
      run = build(
        :test_suite_run,
        test_suite: build(:test_suite, agent: build(:agent, operation: build(:operation, tenant:))),
      )

      expect(policy_class.new(admin, run).resolved_tenant_id(run)).to eq(tenant.id)
    end

    it "returns nil when a record has no tenant path" do
      expect(policy_class.new(admin, Object.new).resolved_tenant_id(Object.new)).to be_nil
    end

    it "returns nil when an associated record does not expose an operation" do
      target = Struct.new(:agent).new(Object.new)

      expect(policy_class.new(admin, target).resolved_operation(target)).to be_nil
    end

    it "returns nil when tenant resolution is asked for nil" do
      expect(policy_class.new(admin, nil).resolved_tenant_id(nil)).to be_nil
    end

    it "treats a missing user as not being a system admin" do
      expect(policy_class.new(nil, nil).system_admin_user?).to be(false)
    end

    it "returns the headquarter read-only reason for mutation queries in Headquarter" do
      headquarter = create(:operation, :headquarter, tenant:)

      Current.set(operation: headquarter) do
        expect(policy_class.new(admin, Agent).denied_reason(:create?)).to eq(
          ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE,
        )
      end
    end
  end
end
