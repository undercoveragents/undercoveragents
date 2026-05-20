# frozen_string_literal: true

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
