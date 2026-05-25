# frozen_string_literal: true

require "rails_helper"

RSpec.describe Costs::Scope do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:other_operation) { create(:operation, tenant:) }
  let(:model_record) { create(:model) }

  it "returns no messages for unsupported limit target types" do
    limit = build(:cost_limit, tenant:, target_type: "unknown")
    scope = described_class.new(tenant:)

    result = scope.send(:apply_limit_target, Message.all, limit)

    expect(result).to be_empty
  end

  it "filters chats and messages by attributed tenant and operation ids", :aggregate_failures do
    visible_chat = create(:chat, tenant:, operation:, model: model_record)
    create(:message, chat: visible_chat, model: model_record)

    hidden_chat = create(:chat, tenant:, operation: other_operation, model: model_record)
    create(:message, chat: hidden_chat, model: model_record)

    foreign_tenant = create(:tenant).tap(&:ensure_core_resources!)
    foreign_chat = create(
      :chat,
      tenant: foreign_tenant,
      operation: foreign_tenant.default_operation,
      model: model_record,
    )
    create(:message, chat: foreign_chat, model: model_record)

    scope = described_class.new(tenant:, operation:)

    expect(scope.chats).to contain_exactly(visible_chat)
    expect(scope.messages.pluck(:chat_id).uniq).to eq([visible_chat.id])
  end

  it "filters tenant-wide chats by range when no operation is selected" do
    current_time = Time.zone.parse("2026-05-20 12:00:00")
    recent_chat = create(:chat, tenant:, operation:, model: model_record, created_at: current_time)
    other_recent_chat = create(
      :chat,
      tenant:,
      operation: other_operation,
      model: model_record,
      created_at: current_time - 1.day,
    )
    create(:chat, tenant:, operation:, model: model_record, created_at: current_time - 7.days)

    scope = described_class.new(tenant:, range: (current_time - 2.days)..current_time)

    expect(scope.chats).to contain_exactly(recent_chat, other_recent_chat)
  end
end
