# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentDesigner::ChatSnapshot do
  def create_metric_message(chat, **attributes)
    create(
      :message,
      chat:,
      **attributes,
    )
  end

  def build_snapshot_with_child_metrics
    chat = create(:chat)
    create_metric_message(
      chat,
      input_tokens: 10,
      output_tokens: 2,
      cached_tokens: 1,
      cache_creation_tokens: 3,
      thinking_tokens: 4,
    )
    child_chat = create(:chat, parent_chat: chat)
    child_message = create_metric_message(
      child_chat,
      input_tokens: 5,
      output_tokens: 6,
      cached_tokens: 7,
      cache_creation_tokens: 8,
      thinking_tokens: 9,
    )

    [described_class.new(chat:), child_chat, child_message]
  end

  it "returns empty child messages when there are no child chats" do
    chat = create(:chat)
    snapshot = described_class.new(chat:)

    expect(snapshot.child_messages).to eq([])
  end

  it "loads child messages and aggregates child chat metrics" do
    snapshot, child_chat, child_message = build_snapshot_with_child_metrics

    expect(snapshot.child_messages.map(&:id)).to eq([child_message.id])
    expect(snapshot.child_chat_metrics.fetch(child_chat.id)).to include(cost: be > 0)
    expect(snapshot.child_chat_metrics.fetch(child_chat.id).fetch(:tokens)).to eq(
      input: child_message.total_input_activity_tokens,
      output: 6,
    )
    expect(snapshot.token_totals).to include(
      input: 15,
      output: 8,
      cached: 8,
      cache_creation: 11,
      thinking: 13,
    )
  end
end
