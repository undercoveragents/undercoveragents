# frozen_string_literal: true

# == Schema Information
#
# Table name: operations
# Database name: primary
#
#  id          :bigint           not null, primary key
#  description :text
#  icon        :string           default("fa-solid fa-briefcase")
#  name        :string           not null
#  slug        :string           not null
#  system      :boolean          default(FALSE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  tenant_id   :bigint           not null
#
# Indexes
#
#  index_operations_on_slug                (slug) UNIQUE
#  index_operations_on_system              (system)
#  index_operations_on_tenant_id           (tenant_id)
#  index_operations_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id)
#
require "rails_helper"

RSpec.describe Operation do
  describe "associations" do
    it { is_expected.to have_many(:agents).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:missions).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:tools).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:skill_catalogs).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:rag_flows).dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject(:operation) { build(:operation) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:tenant_id).case_insensitive }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_length_of(:description).is_at_most(500) }
  end

  describe "scopes" do
    it "orders by name" do
      tenant = create(:tenant)
      op_b = create(:operation, tenant:, name: "Bravo")
      op_a = create(:operation, tenant:, name: "Alpha")

      expect(described_class.for_tenant(tenant).ordered).to eq([op_a, op_b])
    end

    it "filters user-managed operations" do
      sys = create(:operation, :system)
      user_op = create(:operation)
      expect(described_class.user_managed).to include(user_op)
      expect(described_class.user_managed).not_to include(sys)
    end
  end

  describe ".headquarter" do
    it "returns the Headquarter operation" do
      tenant = create(:tenant)
      hq = create(:operation, :headquarter, tenant:)

      expect(described_class.headquarter(tenant)).to eq(hq)
    end

    it "returns nil when no tenant can be resolved" do
      allow(Tenant).to receive(:default_tenant).and_return(nil)

      expect(described_class.headquarter(nil)).to be_nil
    end
  end

  describe ".default_operation" do
    it "returns the Default operation" do
      tenant = create(:tenant)
      default_op = create(:operation, :default, tenant:)

      expect(described_class.default_operation(tenant)).to eq(default_op)
    end

    it "returns nil when no tenant can be resolved" do
      allow(Tenant).to receive(:default_tenant).and_return(nil)

      expect(described_class.default_operation(nil)).to be_nil
    end
  end

  describe ".current_operation_id" do
    it "returns the operation id from the session" do
      session = { current_operation_id: 42 }
      expect(described_class.current_operation_id(session)).to eq(42)
    end

    it "returns nil when no operation is set" do
      session = {}
      expect(described_class.current_operation_id(session)).to be_nil
    end
  end

  describe ".set_current_operation" do
    it "stores the operation id in the session" do
      session = {}
      op = create(:operation)
      described_class.set_current_operation(session, op)
      expect(session[:current_operation_id]).to eq(op.id)
    end

    it "stores nil when operation is nil" do
      session = { current_operation_id: 42 }
      described_class.set_current_operation(session, nil)
      expect(session[:current_operation_id]).to be_nil
    end
  end

  describe ".preload_counts" do
    let(:populated_operation) { create(:operation, name: "Alpha Ops") }
    let(:empty_operation) { create(:operation, name: "Beta Ops") }

    before do
      create(:agent, operation: populated_operation)
      create(:mission, operation: populated_operation)
      create(:tool, :sql_query, operation: populated_operation)
      create(:skill_catalog, operation: populated_operation)
      create(:rag_flow, operation: populated_operation)

      described_class.preload_counts([populated_operation, empty_operation])
    end

    it "assigns grouped counts to each operation" do
      aggregate_failures do
        expect(populated_operation.agent_count).to eq(1)
        expect(populated_operation.mission_count).to eq(1)
        expect(populated_operation.tool_count).to eq(1)
        expect(populated_operation.skill_catalog_count).to eq(1)
        expect(populated_operation.rag_flow_count).to eq(1)
        expect(empty_operation.agent_count).to eq(0)
        expect(empty_operation.mission_count).to eq(0)
        expect(empty_operation.tool_count).to eq(0)
        expect(empty_operation.skill_catalog_count).to eq(0)
        expect(empty_operation.rag_flow_count).to eq(0)
        expect(populated_operation).not_to be_destroyable
        expect(empty_operation).to be_destroyable
      end
    end

    it "returns when no operations are provided" do
      expect { described_class.preload_counts([]) }.not_to raise_error
    end
  end

  describe "#headquarter?" do
    it "returns true for the Headquarter system operation" do
      hq = build(:operation, :headquarter)
      expect(hq).to be_headquarter
    end

    it "returns false for non-system operations" do
      op = build(:operation)
      expect(op).not_to be_headquarter
    end
  end

  describe "#destroyable?" do
    it "returns false for system operations" do
      op = build(:operation, :system)
      expect(op).not_to be_destroyable
    end

    it "returns true for empty user-managed operations" do
      op = create(:operation)
      expect(op).to be_destroyable
    end

    it "returns false when operation has agents" do
      op = create(:operation)
      create(:agent, operation: op)
      expect(op).not_to be_destroyable
    end

    it "returns false when operation has skill catalogs" do
      op = create(:operation)
      create(:skill_catalog, operation: op)

      expect(op).not_to be_destroyable
    end

    it "falls back to association sizes for each count helper" do
      op = create(:operation)
      create(:agent, operation: op)
      create(:mission, operation: op)
      create(:tool, :sql_query, operation: op)
      create(:skill_catalog, operation: op)
      create(:rag_flow, operation: op)

      aggregate_failures do
        expect(op.agent_count).to eq(1)
        expect(op.mission_count).to eq(1)
        expect(op.tool_count).to eq(1)
        expect(op.skill_catalog_count).to eq(1)
        expect(op.rag_flow_count).to eq(1)
      end
    end
  end

  describe "friendly_id" do
    it "generates a slug from the name" do
      op = create(:operation, name: "My Cool Operation")
      expect(op.slug).to eq("my-cool-operation")
    end
  end
end
