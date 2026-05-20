# frozen_string_literal: true

# == Schema Information
#
# Table name: message_feedbacks
# Database name: primary
#
#  id         :bigint           not null, primary key
#  category   :string
#  comment    :text
#  value      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  chat_id    :bigint           not null
#  message_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_message_feedbacks_on_chat_id                 (chat_id)
#  index_message_feedbacks_on_message_id              (message_id)
#  index_message_feedbacks_on_message_id_and_user_id  (message_id,user_id) UNIQUE
#  index_message_feedbacks_on_user_id                 (user_id)
#  index_message_feedbacks_on_value                   (value)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (message_id => messages.id)
#  fk_rails_...  (user_id => users.id)
#
class MessageFeedback < ApplicationRecord
  NEGATIVE_CATEGORIES = [
    "incorrect",
    "incomplete",
    "harmful",
    "formatting",
    "other",
  ].freeze
  VALUES = ["positive", "negative"].freeze

  belongs_to :message
  belongs_to :chat
  belongs_to :user

  validates :value, presence: true, inclusion: { in: VALUES }
  validates :category, inclusion: { in: NEGATIVE_CATEGORIES }, allow_blank: true
  validates :user_id, uniqueness: { scope: :message_id }
  validate :assistant_message_only
  validate :chat_matches_message

  before_validation :assign_chat_from_message
  before_validation :normalize_positive_feedback

  def positive?
    value == "positive"
  end

  def negative?
    value == "negative"
  end

  private

  def assign_chat_from_message
    self.chat ||= message&.chat
  end

  def normalize_positive_feedback
    return unless positive?

    self.category = nil
    self.comment = nil
  end

  def assistant_message_only
    return if message&.assistant?

    errors.add(:message, "must be an assistant message")
  end

  def chat_matches_message
    return if chat.blank? || message.blank? || chat == message.chat

    errors.add(:chat, "must match the message chat")
  end
end
