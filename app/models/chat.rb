# frozen_string_literal: true

# == Schema Information
#
# Table name: chats
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  child_chats_count       :integer          default(0), not null
#  execution_context       :string           default("playground"), not null
#  messages_count          :integer          default(0), not null
#  status                  :string           default("idle"), not null
#  title                   :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  agent_id                :bigint
#  channel_conversation_id :bigint
#  channel_id              :bigint
#  channel_target_id       :bigint
#  client_id               :bigint
#  mission_id              :bigint
#  model_id                :bigint
#  parent_chat_id          :bigint
#  telegram_chat_id        :bigint
#  user_id                 :bigint
#
# Indexes
#
#  index_chats_on_agent_id                 (agent_id)
#  index_chats_on_channel_conversation_id  (channel_conversation_id)
#  index_chats_on_channel_id               (channel_id)
#  index_chats_on_channel_target_id        (channel_target_id)
#  index_chats_on_client_id                (client_id)
#  index_chats_on_execution_context        (execution_context)
#  index_chats_on_mission_id               (mission_id)
#  index_chats_on_model_id                 (model_id)
#  index_chats_on_parent_chat_id           (parent_chat_id)
#  index_chats_on_telegram_chat_id         (telegram_chat_id)
#  index_chats_on_user_id                  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (agent_id => agents.id)
#  fk_rails_...  (channel_conversation_id => channel_conversations.id)
#  fk_rails_...  (channel_id => channels.id)
#  fk_rails_...  (channel_target_id => channel_targets.id)
#  fk_rails_...  (client_id => clients.id)
#  fk_rails_...  (mission_id => missions.id)
#  fk_rails_...  (model_id => models.id)
#  fk_rails_...  (parent_chat_id => chats.id)
#  fk_rails_...  (user_id => users.id)
#
class Chat < ApplicationRecord
  include DurationTracking

  include ChatResponseDispatch

  DEFAULT_TITLE = "New chat"

  # Custom error raised when chat streaming is cancelled by user
  class CancelledError < StandardError; end

  acts_as_chat messages_foreign_key: :chat_id

  enum :status, { idle: "idle", streaming: "streaming", cancelled: "cancelled" }, default: :idle
  enum :execution_context, {
    playground: "playground",
    application: "application",
    test: "test",
    system: "system",
    channel: "channel",
    user: "user",
    telegram: "telegram", # Used by Telegram plugin — kept for DB compatibility
    mission: "mission",
  }, default: :playground
  belongs_to :agent, optional: true
  belongs_to :channel, optional: true
  belongs_to :channel_target, optional: true
  belongs_to :channel_conversation, optional: true
  belongs_to :client, optional: true
  belongs_to :mission, optional: true
  belongs_to :parent_chat, class_name: "Chat", optional: true,
                           counter_cache: :child_chats_count
  belongs_to :user, optional: true
  has_many :child_chats, class_name: "Chat", foreign_key: :parent_chat_id,
                         dependent: :nullify, inverse_of: :parent_chat

  scope :for_agent, ->(agent) { where(agent_id: agent.id) }
  scope :for_channel, ->(channel) { where(channel:) }
  scope :for_client, ->(client) { where(client:) }
  scope :for_mission, ->(mission) { where(mission:) }
  scope :for_user, ->(user) { where(user:) }
  scope :recent, -> { order(updated_at: :desc) }

  after_initialize :set_default_title, if: :new_record?
  def self.ransackable_attributes(_auth_object = nil)
    [
      "id", "title", "execution_context", "agent_id", "mission_id", "model_id", "parent_chat_id",
      "created_at", "updated_at",
    ]
  end

  def display_title
    title.presence || DEFAULT_TITLE
  end

  def display_title_for_ui(max_length: 40)
    visible_title = display_title

    if application? && agent&.name.present?
      visible_title = visible_title.sub(/\A#{Regexp.escape(agent.name)}\s*[—–-]?\s*/, "")
      visible_title = DEFAULT_TITLE if visible_title.blank?
    end

    visible_title.truncate(max_length)
  end

  def title_dom_id
    "chat-#{id}-title"
  end

  def broadcast_title_update
    ActionCable.server.broadcast(
      ui_stream_channel_name,
      ui_stream_payload(
        type: "chat_title",
        chat_id: id,
        target: title_dom_id,
        title: display_title_for_ui,
      ),
    )
  end

  def playground_agent_supported?
    agent&.playground_compatible?
  end

  def ask(*, **kwargs, &)
    setup_duration_tracking unless @duration_tracking_initialized

    with_current_chat_context do
      if kwargs.empty?
        super(*, &)
      else
        super(*, **kwargs, &)
      end
    end
  end

  def complete(...)
    @_duration_complete_start = duration_monotonic_now
    super
  end

  # Calculates the total cost of the chat in USD based on token usage and model pricing.
  # Returns nil if no model is associated or if pricing information is unavailable.
  # @return [BigDecimal, nil] The total cost in USD
  def calculate_cost
    messages.sum { |message| message.calculate_cost || 0 }
  end

  def broadcast_status_update(phase: nil)
    ActionCable.server.broadcast(
      ui_stream_channel_name,
      ui_stream_payload(
        type: "status",
        chat_id: id,
        status:,
        phase:,
      ),
    )
  end

  def self.user_stream_channel_name_for(user)
    user_id = user.respond_to?(:id) ? user.id : user
    "chat_user_stream_#{user_id}"
  end

  def self.signed_stream_name(stream_name)
    Rails.application.message_verifier(:chat_stream).generate(stream_name.to_s, purpose: "chat_stream")
  end

  def self.verified_stream_name(token)
    Rails.application.message_verifier(:chat_stream).verified(token, purpose: "chat_stream")
  end

  def stream_channel_name
    "chat_stream_#{id}"
  end

  def ui_stream_channel_name
    return self.class.user_stream_channel_name_for(user_id) if user_id.present?
    return parent_chat.ui_stream_channel_name if parent_chat.present?

    stream_channel_name
  end

  def signed_ui_stream_name
    self.class.signed_stream_name(ui_stream_channel_name)
  end

  def ui_stream_payload(payload = {})
    payload.deep_symbolize_keys.merge(
      {
        parent_chat_id:,
        agent_name: agent&.name,
      }.compact,
    )
  end

  # Override RubyLLM's to_llm to compute a set of stale tool-result message IDs
  # whose content will be replaced with a short stub by Message#to_llm. This
  # reduces the input-token footprint of long tool-heavy chats (e.g. the mission
  # designer) without losing any data: the audit log on the AR side is untouched,
  # only the in-memory copy shipped to the LLM provider is compacted.
  def to_llm
    @stale_message_ids = Chats::MessageCompactor.new(self).stale_message_ids
    super
  end

  # @return [Set<Integer>] AR message IDs whose content should be stubbed for the
  #   current to_llm rebuild. Returns an empty set when compaction has not been
  #   computed yet (e.g. direct Message#to_llm calls outside a to_llm rebuild).
  def stale_message_ids
    @stale_message_ids || Set.new
  end

  def with_runtime_instructions(instructions, append: false, replace: nil)
    append = append_instructions?(append:, replace:)
    store_runtime_instruction(instructions, append:)
    to_llm
    self
  end

  private

  def reapply_runtime_instructions(chat)
    return if runtime_instructions.empty?

    runtime_instructions.each do |instruction|
      chat.with_instructions(instruction, append: true)
    end
  end

  def set_default_title
    self.title ||= DEFAULT_TITLE
  end

  def with_current_chat_context(&)
    Current.set(chat: self, &)
  end
end
