# frozen_string_literal: true

# == Schema Information
#
# Table name: channel_conversations
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  metadata                 :jsonb            not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  channel_id               :bigint           not null
#  channel_identity_id      :bigint
#  channel_target_id        :bigint
#  chat_id                  :bigint
#  external_conversation_id :string           not null
#  external_thread_id       :string           default(""), not null
#  mission_run_id           :bigint
#
# Indexes
#
#  index_channel_conversations_on_channel_id           (channel_id)
#  index_channel_conversations_on_channel_identity_id  (channel_identity_id)
#  index_channel_conversations_on_channel_target_id    (channel_target_id)
#  index_channel_conversations_on_chat_id              (chat_id)
#  index_channel_conversations_on_external_ids         (channel_id,external_conversation_id,external_thread_id) UNIQUE
#  index_channel_conversations_on_mission_run_id       (mission_run_id)
#
# Foreign Keys
#
#  fk_rails_...  (channel_id => channels.id)
#  fk_rails_...  (channel_identity_id => channel_identities.id)
#  fk_rails_...  (channel_target_id => channel_targets.id)
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (mission_run_id => mission_runs.id)
#
class ChannelConversation < ApplicationRecord
  belongs_to :channel
  belongs_to :channel_target, optional: true
  belongs_to :channel_identity, optional: true
  belongs_to :chat, optional: true
  belongs_to :mission_run, optional: true

  validates :external_conversation_id, presence: true, uniqueness: { scope: [:channel_id, :external_thread_id] }
  validates :external_thread_id, length: { maximum: 255 }, allow_blank: true
  validate :records_must_belong_to_channel

  attribute :metadata, :jsonb, default: -> { {} }

  before_validation :ensure_metadata

  private

  def ensure_metadata
    self.metadata = {} unless metadata.is_a?(Hash)
  end

  def records_must_belong_to_channel
    validate_channel_record(channel_target, :channel_target)
    validate_channel_record(channel_identity, :channel_identity)
    validate_channel_record(chat, :chat)
    validate_channel_record(mission_run, :mission_run)
  end

  def validate_channel_record(record, attribute)
    return if record.blank?
    return if record.channel_id == channel_id

    errors.add(attribute, "must belong to the same channel")
  end
end
