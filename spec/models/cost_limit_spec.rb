# frozen_string_literal: true

require "rails_helper"

RSpec.describe CostLimit do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }

  it "labels tenant, operation, execution context, and record targets" do
    user = create(:user, tenant:, email: "owner@example.test")

    expect(build(:cost_limit, tenant:, target_type: "tenant").target_label).to eq(tenant.name)
    expect(build(:cost_limit, :for_operation, tenant:, operation:).target_record).to eq(operation)
    expect(build(:cost_limit, tenant:, target_type: "execution_context", target_key: "application").target_label)
      .to eq("application")
    expect(build(:cost_limit, tenant:, target_type: "user", target_id: user.id).target_label)
      .to eq("owner@example.test")
  end

  it "validates target references and tenant ownership" do
    foreign_tenant = create(:tenant).tap(&:ensure_core_resources!)
    foreign_agent = create(:agent, operation: foreign_tenant.default_operation)
    invalid = build(:cost_limit, tenant:, operation:, target_type: "agent", target_id: foreign_agent.id)
    invalid_operation = build(
      :cost_limit,
      :for_operation,
      tenant:,
      operation: foreign_tenant.default_operation,
      target_type: "tenant",
    )

    expect(invalid).not_to be_valid
    expect(invalid.errors[:target_id]).to include("must belong to the same tenant")
    expect(invalid_operation).not_to be_valid
    expect(invalid_operation.errors[:operation]).to include("must belong to the same tenant")
  end

  it "rejects invalid target shapes" do
    invalid_tenant = build(:cost_limit, tenant:, target_type: "tenant", target_id: 1, target_key: "x")
    invalid_operation = build(:cost_limit, tenant:, target_type: "operation", target_id: 1, target_key: "x")
    invalid_context = build(:cost_limit, tenant:, target_type: "execution_context", target_key: "invalid", target_id: 1)
    invalid_agent = build(:cost_limit, tenant:, target_type: "agent", target_key: "x")

    expect(invalid_tenant).not_to be_valid
    expect(invalid_operation).not_to be_valid
    expect(invalid_context).not_to be_valid
    expect(invalid_agent).not_to be_valid
  end

  it "handles missing and model record targets" do
    model_record = create(:model)
    missing = build(:cost_limit, tenant:, target_type: "model", target_id: Model.maximum(:id).to_i + 100)
    valid_model = build(:cost_limit, tenant:, target_type: "model", target_id: model_record.id)

    expect(build(:cost_limit, tenant:, target_type: "agent").target_record).to be_nil
    expect(build(:cost_limit, tenant:, target_type: "unknown").target_record).to be_nil
    expect(build(:cost_limit, tenant:, target_type: "agent", target_id: nil).target_label).to eq("Unknown agent")
    expect(missing).not_to be_valid
    expect(valid_model).to be_valid
  end
end
