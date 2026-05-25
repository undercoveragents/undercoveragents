# frozen_string_literal: true

require "rails_helper"

RSpec.describe CostDesigner::ReadCostAnalysisTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:model_record) { create(:model) }
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

  it "returns dashboard-equivalent cost summary text" do
    chat = create(:chat, tenant:, operation:, model: model_record)
    create(:message, chat:, model: model_record, input_tokens: 12, output_tokens: 4).update_columns( # rubocop:disable Rails/SkipsModelValidations
      cost_usd: 2.5,
      cost_calculated_at: Time.current,
    )

    result = described_class.new(runtime_context:).execute(period: "all_time", operation_id: operation.slug)

    expect(result).to include("## Cost Analysis")
    expect(result).to include("- Operation: #{operation.name}")
    expect(result).to include("- Total spend: $2.500000")
  end

  it "reports active limit counts and lookup errors" do
    create(:cost_limit, tenant:, period: "all_time", amount_usd: 10)
    tool = described_class.new(runtime_context:)

    expect(tool.execute(period: "all_time")).to include("- Active limits: 1")
    expect(tool.execute(period: nil, operation_id: "all")).to include("- Period: Rolling 30 days")
    expect(tool.execute(period: "invalid")).to include("- Period: Rolling 30 days")
    expect(tool.execute(operation_id: "missing")).to include("Error: Operation 'missing' was not found.")
  end
end
