# frozen_string_literal: true

require "rails_helper"

RSpec.describe CostDesigner::ReadCostLimitTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:runtime_context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: nil,
      user: create(:user, :admin, tenant:),
      tenant:,
      operation:,
    )
  end

  it "lists every cost limit when no ID is supplied" do
    create(:cost_limit, tenant:, name: "Tenant cap")

    result = described_class.new(runtime_context:).execute

    expect(result).to include("## Cost Limits")
    expect(result).to include("Tenant cap")
  end

  it "reports an empty state when no limits exist" do
    expect(described_class.new(runtime_context:).execute).to eq("No cost limits configured.")
  end

  it "reads one limit by id and by unique name" do
    limit = create(:cost_limit, tenant:, name: "Application limit", period: "all_time")
    operation_limit = create(:cost_limit, :for_operation, tenant:, operation:, name: "Operation limit")
    tool = described_class.new(runtime_context:)

    expect(tool.execute(cost_limit_id: limit.id)).to include("## Cost Limit", "Application limit", "All operations")
    expect(tool.execute(cost_limit_id: operation_limit.id)).to include("- Operation scope: #{operation.name}")
    expect(tool.execute(cost_limit_id: "Application limit")).to include("Application limit")
  end

  it "returns lookup errors for missing or ambiguous names" do
    create(:cost_limit, tenant:, name: "Duplicate")
    create(:cost_limit, tenant:, name: "Duplicate")
    tool = described_class.new(runtime_context:)

    expect(tool.execute(cost_limit_id: "missing")).to include("Error: Cost limit 'missing' was not found.")
    expect(tool.execute(cost_limit_id: "Duplicate")).to include("Multiple cost limits named")
  end
end
