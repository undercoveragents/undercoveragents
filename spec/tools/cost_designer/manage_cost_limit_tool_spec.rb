# frozen_string_literal: true

require "rails_helper"

RSpec.describe CostDesigner::ManageCostLimitTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:runtime_context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: nil,
      user:,
      tenant:,
      operation:,
    )
  end

  it "creates and toggles a cost limit" do
    tool = described_class.new(runtime_context:)

    result = tool.execute(
      action: "create",
      attributes: {
        name: "Monthly workspace cap",
        target_type: "operation",
        operation_id: operation.id,
        period: "month",
        amount_usd: "20.00",
        warning_threshold_percent: 80,
        enforcement_mode: "hard_stop",
      },
    )
    limit = tenant.cost_limits.find_by!(name: "Monthly workspace cap")

    expect(result).to include("Created cost limit `#{limit.id}`")
    expect(tool.execute(action: "toggle", cost_limit_id: limit.id)).to include("Disabled cost limit")
    expect(limit.reload.enabled?).to be(false)
  end

  it "updates and deletes a cost limit" do
    limit = create(:cost_limit, tenant:, name: "Old cap")
    tool = described_class.new(runtime_context:)

    expect(tool.execute(action: "update", cost_limit_id: limit.id, attributes: { name: "New cap" }))
      .to include("Updated cost limit")
    expect(limit.reload.name).to eq("New cap")

    expect(tool.execute(action: "delete", cost_limit_id: limit.id, confirm_destroy: false))
      .to eq("Error: confirm_destroy must be true for delete.")
    expect(tool.execute(action: "delete", cost_limit_id: limit.id, confirm_destroy: true))
      .to include("Deleted cost limit")
  end

  it "returns validation and argument errors" do
    tool = described_class.new(runtime_context:)

    expect(tool.execute(action: "create", attributes: { name: "" })).to include("can't be blank")
    expect(tool.execute(action: "archive")).to include("Unknown action")
    expect(tool.execute(action: "toggle")).to include("Provide cost_limit_id")
  end

  it "returns invalid attribute errors" do
    tool = described_class.new(runtime_context:)

    expect(tool.execute(action: "create", attributes: { name: "Bad", unknown: true })).to include("Unknown")
    expect(tool.execute(action: "create", attributes: "[]")).to include("Expected a JSON object")
    expect(tool.execute(action: "create", attributes: nil)).to include("Expected attributes")
  end

  it "accepts JSON and ActionController parameters" do
    tool = described_class.new(runtime_context:)
    json = {
      name: "JSON cap",
      target_type: "tenant",
      period: "month",
      amount_usd: "15.00",
    }.to_json
    params = ActionController::Parameters.new(name: "Params cap", amount_usd: "20.00")

    expect(tool.execute(action: "create", attributes: json)).to include("Created cost limit")
    limit = tenant.cost_limits.find_by!(name: "JSON cap")
    expect(tool.execute(action: "toggle", cost_limit_id: limit.id)).to include("Disabled cost limit")
    expect(tool.execute(action: "toggle", cost_limit_id: limit.id)).to include("Enabled cost limit")
    expect(tool.execute(action: "update", cost_limit_id: limit.id, attributes: params)).to include("Updated")
    expect(limit.reload.name).to eq("Params cap")
  end

  it "resolves tenant and operation from runtime or Current context" do
    tool = described_class.new(runtime_context:)

    expect(tool.send(:tenant)).to eq(tenant)
    expect(tool.send(:operation)).to eq(operation)
  end

  it "falls back to Current tenant and operation" do
    Current.tenant = tenant
    Current.operation = operation
    tool = described_class.new(runtime_context: nil)

    expect(tool.send(:tenant)).to eq(tenant)
    expect(tool.send(:operation)).to eq(operation)
  ensure
    Current.reset
  end

  it "falls back to the current tenant default operation" do
    Current.tenant = tenant
    tool = described_class.new(runtime_context: nil)

    expect(tool.send(:operation)).to eq(operation)
  ensure
    Current.reset
  end

  it "returns nil when no operation context can be resolved" do
    tool = described_class.new(runtime_context: nil)
    allow(tool).to receive(:tenant).and_return(nil)

    expect(tool.send(:operation)).to be_nil
  end

  it "enforces cost limit policy permissions" do
    regular_user = create(:user, tenant:)
    context = runtime_context.with(user: regular_user)
    tool = described_class.new(runtime_context: context)

    result = tool.execute(
      action: "create",
      attributes: {
        name: "Denied limit",
        target_type: "tenant",
        period: "month",
        amount_usd: "20.00",
      },
    )

    expect(result).to include("Error:")
    expect(tenant.cost_limits.find_by(name: "Denied limit")).to be_nil
  end
end
