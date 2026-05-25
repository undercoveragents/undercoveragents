# frozen_string_literal: true

require "rails_helper"

RSpec.describe Costs::AggregateQuery do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:other_operation) { create(:operation, tenant:, name: "Support") }
  let(:model_record) { create(:model) }

  def create_costed_message(operation:, cost:, **attributes)
    created_at = attributes.fetch(:created_at, Time.current)
    execution_context = attributes.fetch(:execution_context, "playground")
    message_model = attributes.fetch(:message_model, model_record)
    chat_model = attributes.fetch(:chat_model, model_record)
    chat = create(:chat, tenant:, operation:, model: chat_model, created_at:, execution_context:)
    create(:message, chat:, model: message_model, created_at:).tap do |message|
      message.update_columns( # rubocop:disable Rails/SkipsModelValidations
        cost_usd: cost,
        cost_calculated_at: created_at,
      )
    end
  end

  it "ignores unknown dimensions" do
    create_costed_message(operation:, cost: BigDecimal("1.0"))

    result = described_class.new(Costs::Scope.new(tenant:).messages).by_dimension("unknown")

    expect(result).to be_empty
  end

  it "summarizes persisted cost snapshots and groups them by operation and day", :aggregate_failures do
    first_message = create_costed_message(
      operation:,
      cost: BigDecimal("4.25"),
      created_at: Time.zone.parse("2026-05-10 10:00:00"),
    )
    second_message = create_costed_message(
      operation: other_operation,
      cost: BigDecimal("3.00"),
      created_at: Time.zone.parse("2026-05-11 09:00:00"),
    )
    query = described_class.new(Costs::Scope.new(tenant:).messages)
    summary = query.summary
    cost_by_day = query.cost_by_day
    operation_groups = query.by_dimension("operation")

    expect(summary.total_cost).to eq(BigDecimal("7.25"))
    expect(summary.input_tokens).to eq(
      first_message.total_input_activity_tokens + second_message.total_input_activity_tokens,
    )
    expect(summary.chat_count).to eq(2)
    expect(cost_by_day.fetch(Date.new(2026, 5, 10))).to eq(BigDecimal("4.25"))
    expect(cost_by_day.fetch(Date.new(2026, 5, 11))).to eq(BigDecimal("3.0"))
    expect(operation_groups.map { |group| [group.label, group.cost] }).to include(
      [operation.name, BigDecimal("4.25")],
      [other_operation.name, BigDecimal("3.0")],
    )
  end

  it "humanizes execution context groups in SQL" do
    create_costed_message(
      operation:,
      cost: BigDecimal("1.25"),
      created_at: Time.zone.parse("2026-05-12 09:00:00"),
      execution_context: "application",
    )

    result = described_class.new(Costs::Scope.new(tenant:).messages).by_dimension("execution_context")

    expect(result.map { |group| [group.key, group.label] }).to include(["application", "Application"])
  end

  it "uses the chat model when the message model is missing" do
    fallback_model = create(:model, model_id: "fallback-model")
    create_costed_message(
      operation:,
      cost: BigDecimal("2.50"),
      message_model: nil,
      chat_model: fallback_model,
    )

    result = described_class.new(Costs::Scope.new(tenant:).messages).by_dimension("model")

    expect(result.map { |group| [group.key, group.label] }).to include([fallback_model.id, fallback_model.model_id])
  end

  it "ignores uncosted messages" do
    create_costed_message(operation:, cost: BigDecimal("1.50"))
    chat = create(:chat, tenant:, operation:, model: model_record)
    create(:message, chat:, model: model_record).update_columns( # rubocop:disable Rails/SkipsModelValidations
      cost_usd: nil,
      cost_calculated_at: nil,
    )

    summary = described_class.new(Costs::Scope.new(tenant:).messages).summary

    expect(summary.total_cost).to eq(BigDecimal("1.5"))
    expect(summary.message_count).to eq(1)
  end
end
