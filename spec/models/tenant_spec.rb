# frozen_string_literal: true

# == Schema Information
#
# Table name: tenants
# Database name: primary
#
#  id          :bigint           not null, primary key
#  description :text
#  name        :string           not null
#  slug        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_tenants_on_name  (name) UNIQUE
#  index_tenants_on_slug  (slug) UNIQUE
#
require "rails_helper"

RSpec.describe Tenant do
  describe "associations" do
    it { is_expected.to have_many(:users).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:connectors).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:clients).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:api_clients).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:operations).dependent(:destroy) }
    it { is_expected.to have_one(:system_preference).dependent(:destroy) }
  end

  describe "validations" do
    subject(:tenant) { build(:tenant) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).case_insensitive }
    it { is_expected.to validate_length_of(:name).is_at_most(120) }
    it { is_expected.to validate_length_of(:description).is_at_most(500) }
  end

  describe ".default_tenant" do
    it "returns the first ordered tenant when one exists" do
      alpha = create(:tenant, name: "Alpha Tenant")
      create(:tenant, name: "Zeta Tenant")

      expect(described_class.default_tenant).to eq(alpha)
    end

    it "creates the default tenant when none exists" do
      described_class.find_each(&:purge!)

      tenant = described_class.default_tenant

      expect(tenant.name).to eq(described_class::DEFAULT_NAME)
      expect(tenant.description).to eq(described_class::DEFAULT_DESCRIPTION)
    end
  end

  describe "core operations" do
    it "returns the tenant headquarter operation" do
      tenant = create(:tenant)
      headquarter = create(:operation, :headquarter, tenant:)

      expect(tenant.headquarter_operation).to eq(headquarter)
    end

    it "returns the tenant default operation" do
      tenant = create(:tenant)
      default_operation = create(:operation, :default, tenant:)

      expect(tenant.default_operation).to eq(default_operation)
    end

    it "creates the core operations and returns self" do
      tenant = create(:tenant)

      expect(tenant.ensure_core_resources!).to eq(tenant)
      expect(tenant.headquarter_operation).to be_present
      expect(tenant.default_operation).to be_present
    end

    it "creates the core operations only once" do
      tenant = create(:tenant)

      tenant.ensure_core_resources!

      expect { tenant.ensure_core_resources! }.not_to change(Operation, :count)
    end
  end

  describe "#create_initial_admin!" do
    it "creates an active tenant admin with the provided email" do
      tenant = create(:tenant, name: "Northwind")
      tenant.admin_email = "owner@northwind.test"

      credentials = tenant.create_initial_admin!

      expect(credentials.user).to be_persisted
      expect(credentials.user).to have_attributes(
        tenant:,
        email: "owner@northwind.test",
        role: "admin",
        status: "active",
      )
      expect(credentials.password).to be_present
    end

    it "returns a password that satisfies the complexity rules" do
      tenant = create(:tenant, name: "Northwind")
      tenant.admin_email = "owner@northwind.test"

      credentials = tenant.create_initial_admin!

      expect(credentials.password).to match(
        /\A(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[!@#$%^&*\-_]).{#{Tenant::ADMIN_PASSWORD_LENGTH},}\z/o,
      )
      expect(credentials.user.authenticate(credentials.password)).to eq(credentials.user)
    end

    it "builds the initial admin with the provided email" do
      tenant = create(:tenant, name: "Northwind")

      user = tenant.build_initial_admin(email: "owner@northwind.test")

      expect(user).to have_attributes(email: "owner@northwind.test", role: "admin", status: "active")
    end
  end

  describe "#default_tenant?" do
    it "returns true for the resolved default tenant" do
      tenant = create(:tenant, name: "Alpha Tenant")
      create(:tenant, name: "Zeta Tenant")

      expect(tenant).to be_default_tenant
    end

    it "returns false for non-default tenants" do
      create(:tenant, name: "Alpha Tenant")
      tenant = create(:tenant, name: "Zeta Tenant")

      expect(tenant).not_to be_default_tenant
    end
  end

  describe "#destroyable?" do
    it "returns true when the tenant has no dependent records" do
      expect(create(:tenant)).to be_destroyable
    end

    it "returns false when the tenant has users" do
      tenant = create(:tenant)
      create(:user, tenant:)

      expect(tenant).not_to be_destroyable
    end

    it "returns false when the tenant has connectors" do
      tenant = create(:tenant)
      create(:connector, :llm_provider, tenant:)

      expect(tenant).not_to be_destroyable
    end

    it "returns false when the tenant has clients" do
      agent = create(:agent)
      tenant = agent.operation.tenant
      create(:client, agent:, tenant:)

      expect(tenant).not_to be_destroyable
    end

    it "returns false when the tenant has api clients" do
      tenant = create(:tenant)
      create(:api_client, tenant:)

      expect(tenant).not_to be_destroyable
    end

    it "returns false when one of the tenant operations is not destroyable" do
      tenant = create(:tenant)
      operation = create(:operation, tenant:)
      create(:agent, operation:)

      expect(tenant).not_to be_destroyable
    end
  end

  describe "#purge!" do
    it "deletes the tenant and its operations" do
      resources = build_purgeable_tenant

      expect { resources.fetch(:tenant).purge! }.to change(described_class, :count).by(-1)
      expect(Operation.where(tenant_id: resources.fetch(:tenant).id)).to be_empty
    end

    it "removes tenant-owned records, chats, and test suites" do
      resources = build_purgeable_tenant

      resources.fetch(:tenant).purge!

      expect([
               User.exists?(resources.fetch(:user).id),
               Connector.exists?(resources.fetch(:connector).id),
               Client.exists?(resources.fetch(:client).id),
               ApiClient.exists?(resources.fetch(:api_client).id),
               SystemPreference.exists?(resources.fetch(:system_preference).id),
               Agent.exists?(resources.fetch(:agent).id),
               Mission.exists?(resources.fetch(:mission).id),
               Tool.exists?(resources.fetch(:tool).id),
               SkillCatalog.exists?(resources.fetch(:skill_catalog).id),
               RagFlow.exists?(resources.fetch(:rag_flow).id),
               TestSuite.exists?(resources.fetch(:agent_suite).id),
               TestSuite.exists?(resources.fetch(:mission_suite).id),
               Chat.exists?(resources.fetch(:parent_chat).id),
               Chat.exists?(resources.fetch(:child_chat).id),
             ]).to all(be(false))
    end
  end

  def build_purgeable_tenant
    tenant = create(:tenant, name: "Northwind")
    tenant.ensure_core_resources!
    operation = tenant.default_operation

    build_purgeable_resource_map(tenant:, operation:)
  end

  def build_purgeable_resource_map(tenant:, operation:)
    connector = create(:connector, :llm_provider, tenant:)
    user = create(:user, tenant:)
    agent = create(:agent, operation:, llm_connector: connector)
    mission = create(:mission, operation:)

    {
      tenant:,
      connector:,
      user:,
      agent:,
      mission:,
    }.merge(build_purgeable_dependents({ tenant:, operation:, connector:, user:, agent:, mission: }))
  end

  def build_purgeable_dependents(resources)
    tenant = resources.fetch(:tenant)
    operation = resources.fetch(:operation)
    connector = resources.fetch(:connector)
    user = resources.fetch(:user)
    agent = resources.fetch(:agent)
    mission = resources.fetch(:mission)
    parent_chat = create(:chat, user:, agent:, mission:)

    {
      tool: create(:tool, :rag_query, operation:),
      skill_catalog: create(:skill_catalog, operation:),
      rag_flow: create(:rag_flow, operation:),
      client: create(:client, agent:, tenant:),
      api_client: create(:api_client, tenant:),
      system_preference: create(:system_preference, tenant:, llm_connector: connector, model_id: "gpt-4.1"),
      parent_chat:,
      child_chat: create(:chat, parent_chat:),
      agent_suite: create(:test_suite, agent:),
      mission_suite: create(:test_suite, :mission_suite, mission:),
    }
  end
end
