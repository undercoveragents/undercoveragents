# frozen_string_literal: true

# == Schema Information
#
# Table name: telegram_link_requests
# Database name: primary
#
#  id           :bigint           not null, primary key
#  token_digest :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  channel_id   :bigint           not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_telegram_link_requests_on_channel_id              (channel_id)
#  index_telegram_link_requests_on_channel_id_and_user_id  (channel_id,user_id) UNIQUE
#  index_telegram_link_requests_on_token_digest            (token_digest) UNIQUE
#  index_telegram_link_requests_on_user_id                 (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (channel_id => channels.id)
#  fk_rails_...  (user_id => users.id)
#
module Channels
  class TelegramLinkRequest < ApplicationRecord
    self.table_name = "telegram_link_requests"

    belongs_to :channel
    belongs_to :user

    validates :token_digest, presence: true, uniqueness: true
    validates :user_id, uniqueness: { scope: :channel_id }
    validate :channel_must_be_telegram
    validate :user_must_belong_to_channel_tenant

    def self.issue!(channel:, user:)
      request = find_or_initialize_by(channel:, user:)
      raw_token = SecureRandom.alphanumeric(24)
      request.token_digest = digest(raw_token)
      request.save!
      raw_token
    end

    def self.find_by_token(channel:, token:)
      return if token.blank?

      find_by(channel:, token_digest: digest(token))
    end

    def self.clear_for(channel:, user:)
      where(channel:, user:).delete_all
    end

    def self.pending_for(user:, channels:)
      where(user:, channel: channels).index_by(&:channel_id)
    end

    def self.digest(raw_token)
      Digest::SHA256.hexdigest(raw_token.to_s)
    end

    private_class_method :digest

    private

    def channel_must_be_telegram
      return if channel.blank? || channel.channel_type == Channels::Telegram.key

      errors.add(:channel, "must be a Telegram channel")
    end

    def user_must_belong_to_channel_tenant
      return if user.blank? || channel.blank? || user.tenant_id == channel.tenant_id

      errors.add(:user, "must belong to the same tenant as the channel")
    end
  end
end
