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
class Message < ApplicationRecord
  include NullByteSanitizable

  TOTAL_INPUT_ACTIVITY_SQL = <<~SQL.squish.freeze
    COALESCE(messages.input_tokens, 0) +
    COALESCE(messages.cached_tokens, 0) +
    COALESCE(messages.cache_creation_tokens, 0)
  SQL

  acts_as_message tool_calls_foreign_key: :message_id

  enum :role, { user: "user", assistant: "assistant", tool: "tool", system: "system" }
  has_many_attached :attachments
  has_many :message_feedbacks, dependent: :destroy
  # Re-declare to add counter_cache (overrides ruby_llm gem's declaration)
  belongs_to :chat, class_name: "Chat",
                    inverse_of: :messages, counter_cache: true

  delegate :display_content, to: :chat_reference_payload
  delegate :references, to: :chat_reference_payload, prefix: :chat
  scope :visible, -> { where(role: [:user, :assistant]) }

  # NOTE: broadcasts_to was removed intentionally. Streaming is handled by
  # ChatResponseJob via a custom Turbo Stream action (chat_chunk).
  # Completion is signaled by the chat status broadcast (idle). The automatic
  # broadcasts_to callback interfered with the optimistic user message UI and
  # created empty assistant message flashes during streaming.

  before_save :sanitize_content_null_bytes
  before_save :refresh_cost_snapshot, if: :cost_snapshot_refresh_needed?

  # Override extract_content to cache the result.
  # ruby_llm calls this method multiple times per API call (once per message in conversation),
  # which causes repeated downloads of attachments. Caching avoids this overhead.
  def extract_content
    @extract_content ||= super
  end

  # Override RubyLLM's Message#to_llm so that tool-result messages identified as
  # stale by Chats::MessageCompactor ship to the LLM with a short stub content
  # instead of the full original payload. The AR record is not modified — only
  # the in-memory RubyLLM::Message returned here has its content replaced.
  def to_llm
    llm_message = super
    llm_message.content = display_prompt_content if user? && chat_reference_payload.references?
    sanitize_tool_call_arguments_for_llm!(llm_message) if assistant?
    return llm_message unless tool? && chat.stale_message_ids.include?(id)

    llm_message.content = Chats::MessageCompactor::STUB_CONTENT
    llm_message
  end

  # Calculates the cost of this message in USD based on token usage and model pricing.
  # Returns nil if no model is associated or if pricing information is unavailable.
  # Cost formula:
  #   - Standard input tokens: input_tokens * input_per_million / 1_000_000
  #   - Cached input tokens: cached_tokens * cached_input_per_million / 1_000_000
  #   - Cache creation tokens: cache_creation_tokens * cache_creation_per_million / 1_000_000
  #   - Output tokens: output_tokens * output_per_million / 1_000_000
  # @return [BigDecimal, nil] The cost in USD
  def calculate_cost
    calculate_cost_breakdown&.fetch(:total)
  end

  def effective_cost
    cost_usd || calculate_cost || 0
  end

  def calculate_cost_breakdown
    pricing = cost_pricing
    return nil unless pricing

    input_cost = calculate_input_cost(pricing)
    cached_input_cost = calculate_cached_cost(pricing)
    cache_creation_cost = calculate_cache_creation_cost(pricing)
    output_cost = calculate_output_cost(pricing)

    {
      input: input_cost,
      cached_input: cached_input_cost,
      cache_creation: cache_creation_cost,
      output: output_cost,
      total: input_cost + cached_input_cost + cache_creation_cost + output_cost,
      pricing: pricing.deep_dup,
    }
  end

  # Sanitizes null bytes from content, thinking_text and content_raw before saving.
  # PostgreSQL text columns cannot store null bytes, and JSONB columns also reject them.
  def sanitize_content_null_bytes
    self.content = sanitize_null_bytes(content)
    self.thinking_text = sanitize_null_bytes(thinking_text)
    self.content_raw = deep_sanitize_null_bytes(content_raw) if content_raw.present?
  end

  def cost_pricing_model
    model || chat&.model
  end

  def cost_pricing
    cost_pricing_model&.pricing&.dig("text_tokens", "standard")
  end

  def price_per_million(pricing, key, fallback_key = "input_per_million")
    BigDecimal((pricing[key] || pricing[fallback_key]).to_s)
  end

  def self.total_input_activity_sum
    Arel.sql(TOTAL_INPUT_ACTIVITY_SQL)
  end

  def total_input_activity_tokens
    input_tokens.to_i + cached_tokens.to_i + cache_creation_tokens.to_i
  end

  def calculate_input_cost(pricing)
    (input_tokens.to_i * price_per_million(pricing, "input_per_million")) / 1_000_000
  end

  def calculate_cached_cost(pricing)
    (cached_tokens.to_i * price_per_million(pricing, "cached_input_per_million")) / 1_000_000
  end

  def calculate_cache_creation_cost(pricing)
    (cache_creation_tokens.to_i * price_per_million(pricing, "cache_creation_per_million")) / 1_000_000
  end

  def calculate_output_cost(pricing)
    (output_tokens.to_i * price_per_million(pricing, "output_per_million")) / 1_000_000
  end

  def chat_reference_payload
    @chat_reference_payload ||= ChatReferences::MessagePayload.parse(content)
  end

  def display_prompt_content
    chat_reference_payload.prompt_content
  end

  private

  def refresh_cost_snapshot
    Costs::MessageCostSnapshotter.call(self)
  end

  def cost_snapshot_refresh_needed?
    new_record? ||
      will_save_change_to_input_tokens? ||
      will_save_change_to_cached_tokens? ||
      will_save_change_to_cache_creation_tokens? ||
      will_save_change_to_output_tokens? ||
      will_save_change_to_model_id? ||
      will_save_change_to_chat_id?
  end

  def sanitize_tool_call_arguments_for_llm!(llm_message)
    return unless llm_message.respond_to?(:tool_calls)

    Array(tool_calls).each do |tool_call|
      next unless tool_call.respond_to?(:arguments_for_llm)

      llm_tool_call = llm_message.tool_calls&.[](tool_call.tool_call_id)
      next unless llm_tool_call

      llm_tool_call.instance_variable_set(:@arguments, tool_call.arguments_for_llm)
    end
  end
end
