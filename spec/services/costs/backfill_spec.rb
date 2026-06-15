# frozen_string_literal: true

require "rails_helper"

RSpec.describe Costs::Backfill do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, tenant:) }
  let(:model_record) { create(:model) }

  it "backfills missing chat attribution and message cost snapshots", :aggregate_failures do
    agent = create(:agent, operation:)
    chat = create(:chat, tenant:, operation:, user:, agent:, model: model_record)
    chat.update_columns(tenant_id: nil, operation_id: nil) # rubocop:disable Rails/SkipsModelValidations

    message = create(:message, chat:, model: model_record, input_tokens: 120, output_tokens: 80)
    message.update_columns( # rubocop:disable Rails/SkipsModelValidations
      cost_usd: nil,
      input_cost_usd: nil,
      cached_input_cost_usd: nil,
      cache_creation_cost_usd: nil,
      output_cost_usd: nil,
      cost_pricing_snapshot: {},
      cost_calculated_at: nil,
    )

    result = described_class.call

    expect(result.processed_chats).to eq(1)
    expect(result.updated_chats).to eq(1)
    expect(result.processed_messages).to eq(1)
    expect(result.updated_messages).to eq(1)
    expect(chat.reload).to have_attributes(tenant_id: tenant.id, operation_id: operation.id)
    expect(message.reload.cost_usd).to be_present
    expect(message.cost_calculated_at).to be_present
    expect(message.cost_pricing_snapshot).not_to eq({})
  end

  it "skips rows that already have complete attribution and cost snapshots" do
    create(:chat, tenant:, operation:, user:, model: model_record)
    create(:message, chat: create(:chat, tenant:, operation:, model: model_record), model: model_record)

    result = described_class.call

    expect(result.updated_chats).to eq(0)
    expect(result.updated_messages).to eq(0)
  end

  it "logs progress and leaves uninferable rows unchanged", :aggregate_failures do
    say_messages = []
    create(:chat, tenant: nil, operation: nil, user: nil, agent: nil, mission: nil, channel: nil, model: model_record)
    model_without_pricing = create(:model, pricing: {})
    message = create(
      :message,
      chat: create(:chat, tenant:, operation:, model: model_without_pricing),
      model: model_without_pricing,
    )
    message.update_columns( # rubocop:disable Rails/SkipsModelValidations
      cost_usd: nil,
      cost_calculated_at: nil,
      cost_pricing_snapshot: {},
    )

    result = described_class.call(say: ->(message) { say_messages << message })

    expect(result.processed_chats).to eq(1)
    expect(result.updated_chats).to eq(0)
    expect(result.processed_messages).to eq(1)
    expect(result.updated_messages).to eq(0)
    expect(say_messages).to include(
      "Backfilling chat tenant/operation attribution",
      "Updated 0 chats",
      "Backfilling message cost snapshots",
      "Updated 0 messages",
    )
  end
end
