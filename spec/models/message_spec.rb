# frozen_string_literal: true

# == Schema Information
#
# Table name: messages
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  cache_creation_cost_usd :decimal(18, 8)
#  cache_creation_tokens   :integer
#  cached_input_cost_usd   :decimal(18, 8)
#  cached_tokens           :integer
#  content                 :text
#  content_raw             :json
#  cost_calculated_at      :datetime
#  cost_currency           :string           default("USD"), not null
#  cost_pricing_snapshot   :jsonb            not null
#  cost_usd                :decimal(18, 8)
#  duration_ms             :integer
#  input_cost_usd          :decimal(18, 8)
#  input_tokens            :integer
#  output_cost_usd         :decimal(18, 8)
#  output_tokens           :integer
#  role                    :string           not null
#  thinking_signature      :text
#  thinking_text           :text
#  thinking_tokens         :integer
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  chat_id                 :bigint           not null
#  model_id                :bigint
#  tool_call_id            :bigint
#
# Indexes
#
#  index_messages_on_chat_id             (chat_id)
#  index_messages_on_cost_calculated_at  (cost_calculated_at)
#  index_messages_on_cost_usd            (cost_usd)
#  index_messages_on_model_id            (model_id)
#  index_messages_on_role                (role)
#  index_messages_on_tool_call_id        (tool_call_id)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (model_id => models.id)
#  fk_rails_...  (tool_call_id => tool_calls.id)
#
require "rails_helper"

RSpec.describe Message do
  describe "associations" do
    it { is_expected.to belong_to(:chat) }
  end

  describe "enums" do
    subject(:message) { described_class.new }

    it {
      expect(message).to define_enum_for(:role)
        .backed_by_column_of_type(:string)
        .with_values(user: "user", assistant: "assistant", tool: "tool", system: "system")
    }
  end

  describe "#calculate_cost" do
    let(:model_record) do
      create(:model, pricing: {
               "text_tokens" => {
                 "standard" => {
                   "input_per_million" => "3.00",
                   "output_per_million" => "15.00",
                   "cached_input_per_million" => "1.50",
                   "cache_creation_per_million" => "3.75",
                 },
               },
             },)
    end

    let(:chat) { create(:chat, model: model_record) }

    it "calculates cost based on input tokens" do
      message = build(:message, chat:, model: model_record,
                                input_tokens: 1_000_000, output_tokens: 0,
                                cached_tokens: 0, cache_creation_tokens: 0,)

      expect(message.calculate_cost).to eq(BigDecimal("3.0"))
    end

    it "calculates cost based on output tokens" do
      message = build(:message, chat:, model: model_record,
                                input_tokens: 0, output_tokens: 1_000_000,
                                cached_tokens: 0, cache_creation_tokens: 0,)

      expect(message.calculate_cost).to eq(BigDecimal("15.0"))
    end

    it "calculates cost with cached tokens" do
      message = build(:message, chat:, model: model_record,
                                input_tokens: 1_000_000, output_tokens: 0,
                                cached_tokens: 500_000, cache_creation_tokens: 0,)

      # Standard input: 1M * $3/M = $3.00
      # Cached input: 500K * $1.50/M = $0.75
      expect(message.calculate_cost).to eq(BigDecimal("3.75"))
    end

    it "calculates cost with cache creation tokens" do
      message = build(:message, chat:, model: model_record,
                                input_tokens: 0, output_tokens: 0,
                                cached_tokens: 0, cache_creation_tokens: 1_000_000,)

      expect(message.calculate_cost).to eq(BigDecimal("3.75"))
    end

    it "returns nil when no model is associated and chat has no model" do
      chat_no_model = create(:chat)
      chat_no_model.update_column(:model_id, nil) # rubocop:disable Rails/SkipsModelValidations
      chat_no_model.reload
      message = build(:message, chat: chat_no_model, model: nil,
                                input_tokens: 100, output_tokens: 50,
                                cached_tokens: 0, cache_creation_tokens: 0,)

      expect(message.calculate_cost).to be_nil
    end

    it "returns nil when model has no pricing" do
      model_no_pricing = create(:model, pricing: {})
      message = build(:message, chat:, model: model_no_pricing,
                                input_tokens: 100, output_tokens: 50,
                                cached_tokens: 0, cache_creation_tokens: 0,)

      expect(message.calculate_cost).to be_nil
    end

    it "falls back to chat model when message model is nil" do
      message = build(:message, chat:, model: nil,
                                input_tokens: 1_000_000, output_tokens: 0,
                                cached_tokens: 0, cache_creation_tokens: 0,)

      # chat has model_record, so calculate_cost should use that
      expect(message.cost_pricing_model).to eq(model_record)
    end

    it "handles nil token values gracefully" do
      message = build(:message, chat:, model: model_record,
                                input_tokens: nil, output_tokens: nil,
                                cached_tokens: nil, cache_creation_tokens: nil,)

      expect(message.calculate_cost).to eq(BigDecimal("0"))
    end

    it "tracks total input activity across standard and cache buckets" do
      message = build(:message,
                      input_tokens: 100,
                      cached_tokens: 25,
                      cache_creation_tokens: 5,)

      expect(message.total_input_activity_tokens).to eq(130)
    end
  end

  describe "cost snapshots" do
    let(:model_record) { create(:model) }
    let(:chat) { create(:chat, model: model_record) }

    it "persists the calculated cost breakdown when token usage is saved", :aggregate_failures do
      message = create(
        :message,
        chat:,
        model: model_record,
        input_tokens: 1_000_000,
        output_tokens: 1_000_000,
        cached_tokens: 500_000,
        cache_creation_tokens: 0,
      )

      expect(message.cost_usd).to eq(BigDecimal("18.75"))
      expect(message.input_cost_usd).to eq(BigDecimal("3.0"))
      expect(message.cached_input_cost_usd).to eq(BigDecimal("0.75"))
      expect(message.output_cost_usd).to eq(BigDecimal("15.0"))
      expect(message.cost_pricing_snapshot).to include("input_per_million" => "3.00")
      expect(message.cost_calculated_at).to be_present
    end

    it "falls back to dynamic pricing when a legacy row has no snapshot" do
      message = create(:message, chat:, model: model_record, input_tokens: 1_000_000, output_tokens: 0)
      message.update_columns(cost_usd: nil, cost_calculated_at: nil) # rubocop:disable Rails/SkipsModelValidations

      expect(message.reload.effective_cost).to eq(BigDecimal("3.0"))
    end

    it "refreshes the persisted cost snapshot when token usage changes after create", :aggregate_failures do
      message = create(
        :message,
        chat:,
        model: model_record,
        input_tokens: 0,
        output_tokens: 0,
        cached_tokens: 0,
        cache_creation_tokens: 0,
      )

      expect do
        message.update!(input_tokens: 500_000, output_tokens: 250_000)
      end.to change { message.reload.cost_usd }.from(BigDecimal("0")).to(BigDecimal("5.25"))

      expect(message.cost_calculated_at).to be_present
      expect(message.cost_pricing_snapshot).to include("input_per_million" => "3.00")
    end
  end

  describe "#cost_pricing" do
    let(:model_record) do
      create(:model, pricing: {
               "text_tokens" => {
                 "standard" => {
                   "input_per_million" => "3.00",
                   "output_per_million" => "15.00",
                 },
               },
             },)
    end

    let(:chat) { create(:chat, model: model_record) }

    it "returns the pricing hash for the model" do
      message = build(:message, chat:, model: model_record)
      pricing = message.cost_pricing

      expect(pricing).to include("input_per_million" => "3.00")
      expect(pricing).to include("output_per_million" => "15.00")
    end

    it "returns nil when no model has pricing" do
      model_no_pricing = create(:model, pricing: {})
      message = build(:message, chat:, model: model_no_pricing)

      expect(message.cost_pricing).to be_nil
    end

    it "returns nil when both message model and chat are nil" do
      message = described_class.new(role: :assistant, model: nil)
      expect(message.cost_pricing).to be_nil
    end
  end

  describe "#price_per_million" do
    let(:model_record) { create(:model) }
    let(:chat) { create(:chat, model: model_record) }

    it "returns the price for the given key" do
      message = build(:message, chat:, model: model_record)
      pricing = { "input_per_million" => "3.00", "output_per_million" => "15.00" }

      expect(message.price_per_million(pricing, "input_per_million")).to eq(BigDecimal("3.00"))
    end

    it "falls back to the fallback key when primary key is missing" do
      message = build(:message, chat:, model: model_record)
      pricing = { "input_per_million" => "3.00" }

      expect(message.price_per_million(pricing, "missing_key", "input_per_million")).to eq(BigDecimal("3.00"))
    end
  end

  describe "#sanitize_content_null_bytes" do
    let(:chat) { create(:chat) }

    it "removes null bytes from content before saving" do
      message = create(:message, chat:, content: "Hello\u0000World")
      expect(message.reload.content).to eq("HelloWorld")
    end

    it "removes null bytes from thinking_text before saving" do
      message = create(:message, chat:, thinking_text: "Think\u0000ing")
      expect(message.reload.thinking_text).to eq("Thinking")
    end

    it "removes null bytes from content_raw before saving" do
      message = create(:message, chat:, content_raw: { "text" => "Raw\u0000data" })
      expect(message.reload.content_raw).to eq({ "text" => "Rawdata" })
    end

    it "handles nil content gracefully" do
      message = create(:message, chat:, content: nil, thinking_text: nil, content_raw: nil)
      expect(message.reload.content).to be_nil
    end
  end

  describe "#extract_content" do
    let(:chat) { create(:chat) }

    it "caches the result across calls" do
      message = build(:message, chat:, content: "Hello")
      first_call = message.extract_content
      second_call = message.extract_content

      expect(first_call).to equal(second_call)
    end
  end

  describe "chat reference payloads" do
    let(:chat) { create(:chat) }
    let(:packed_content) do
      ChatReferences::MessagePayload.pack(
        content: "Update #launch-plan",
        references: [
          {
            "kind" => "missions",
            "id" => 23,
            "type" => "Mission",
            "label" => "Launch Plan",
            "slug" => "launch-plan",
            "mention" => "#launch-plan",
          },
        ],
      )
    end

    it "exposes display content and references without the hidden marker" do
      message = build(:message, :user, chat:, content: packed_content)

      expect(message.display_content).to eq("Update #launch-plan")
      expect(message.chat_references).to contain_exactly(
        hash_including("id" => 23, "label" => "Launch Plan", "slug" => "launch-plan"),
      )
    end

    it "sends prompt-safe referenced content to the LLM" do
      message = build(:message, :user, chat:, content: packed_content)

      expect(message.to_llm.content).to eq(
        "Update mission id: 23\nReferenced records:\n" \
        "- #launch-plan => Mission: Launch Plan | id: 23 | slug: launch-plan",
      )
    end

    it "leaves plain user messages unchanged for the LLM" do
      message = build(:message, :user, chat:, content: "Hello")

      expect(message.to_llm.content).to eq("Hello")
    end
  end

  describe "#to_llm stale tool-result compaction" do
    let(:chat) { create(:chat) }
    let(:assistant) { chat.messages.create!(role: :assistant, content: "calling tool") }
    let(:tool_call) do
      assistant.tool_calls.create!(
        tool_call_id: "call_xyz",
        name: "read_mission_flow",
        arguments: {},
      )
    end
    let(:tool_message) do
      chat.messages.create!(
        role: :tool,
        content: "Full tool output with lots of tokens",
        tool_call_id: tool_call.id,
      )
    end

    it "returns the original content when the chat has no stale ids" do
      expect(tool_message.to_llm.content).to eq("Full tool output with lots of tokens")
    end

    it "replaces the content with a stub when the message id is in the stale set" do
      tool_message.chat.instance_variable_set(:@stale_message_ids, Set.new([tool_message.id]))

      expect(tool_message.to_llm.content).to eq(Chats::MessageCompactor::STUB_CONTENT)
    end

    it "does not stub non-tool messages even if their id appears in the stale set" do
      assistant.chat.instance_variable_set(:@stale_message_ids, Set.new([assistant.id]))

      expect(assistant.to_llm.content).to eq("calling tool")
    end
  end
end
