# frozen_string_literal: true

# == Schema Information
#
# Table name: messages
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  cache_creation_tokens :integer
#  cached_tokens         :integer
#  content               :text
#  content_raw           :json
#  duration_ms           :integer
#  input_tokens          :integer
#  output_tokens         :integer
#  role                  :string           not null
#  thinking_signature    :text
#  thinking_text         :text
#  thinking_tokens       :integer
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  chat_id               :bigint           not null
#  model_id              :bigint
#  tool_call_id          :bigint
#
# Indexes
#
#  index_messages_on_chat_id       (chat_id)
#  index_messages_on_model_id      (model_id)
#  index_messages_on_role          (role)
#  index_messages_on_tool_call_id  (tool_call_id)
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
    pricing = cost_pricing
    return nil unless pricing

    calculate_input_cost(pricing) +
      calculate_cached_cost(pricing) +
      calculate_cache_creation_cost(pricing) +
      calculate_output_cost(pricing)
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

  def parsed_json_result
    return Llm::JsonResponseParser.failure("Only assistant messages can be parsed") unless assistant?

    Llm::JsonResponseParser.parse(content)
  end

  def parsed_json_content
    result = parsed_json_result
    result.data if result.success?
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
