# frozen_string_literal: true

require "rails_helper"

RSpec.describe Costs::LimitEvaluator do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:model_record) { create(:model) }

  def record_cost(amount)
    chat = create(:chat, tenant:, operation:, model: model_record)
    create(:message, chat:, model: model_record).tap do |message|
      message.update_columns(cost_usd: amount, cost_calculated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  it "reports healthy, warning, and exceeded budget states", :aggregate_failures do
    record_cost(BigDecimal("7.50"))
    limit = create(:cost_limit, tenant:, period: "all_time", amount_usd: 10, warning_threshold_percent: 75)

    warning_result = described_class.call(limit)

    expect(warning_result.status).to eq("warning")
    expect(warning_result.warning?).to be(true)
    expect(warning_result.percent_used).to eq(75)

    record_cost(BigDecimal("2.51"))

    exceeded_result = described_class.call(limit)
    expect(exceeded_result.status).to eq("exceeded")
    expect(exceeded_result.exceeded?).to be(true)
    expect(exceeded_result.remaining).to eq(0)
  end

  it "scopes operation limits to the selected operation" do
    other_operation = create(:operation, tenant:)
    record_cost(BigDecimal("9.00"))
    other_chat = create(:chat, tenant:, operation: other_operation, model: model_record)
    create(:message, chat: other_chat, model: model_record).update_columns( # rubocop:disable Rails/SkipsModelValidations
      cost_usd: 25,
      cost_calculated_at: Time.current,
    )
    limit = create(:cost_limit, :for_operation, tenant:, operation:, period: "all_time", amount_usd: 10)

    result = described_class.call(limit)

    expect(result.spend).to eq(BigDecimal("9.0"))
    expect(result.status).to eq("warning")
  end

  it "supports zero-amount legacy limits and model target scopes" do
    record_cost(BigDecimal("1.25"))
    limit = create(:cost_limit, tenant:, target_type: "model", target_id: model_record.id, period: "all_time")
    limit.update_columns(amount_usd: 0) # rubocop:disable Rails/SkipsModelValidations

    result = described_class.call(limit)

    expect(result.spend).to eq(BigDecimal("1.25"))
    expect(result.percent_used).to eq(0)
  end
end
