# frozen_string_literal: true

module Telegram
  class ProcessMessageJob < ApplicationJob
    queue_as :default

    def perform(channel_id:, tenant_id: nil, **message_payload)
      channel = find_channel(channel_id, tenant_id:)
      raise ActiveRecord::RecordNotFound, "Channel not found" unless channel

      Telegram::MessageProcessor.new(channel:, **message_payload).process
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error "[Telegram::ProcessMessageJob] Channel not found: #{e.message}"
    rescue StandardError => e
      Rails.logger.error "[Telegram::ProcessMessageJob] Error: #{e.message}"
      begin
        channel = find_channel(channel_id, tenant_id:)
        channel&.connector&.send_message(message_payload[:telegram_chat_id], error_message)
      rescue StandardError
        nil
      end
    end

    private

    def find_channel(channel_id, tenant_id: nil)
      scope = Channel.by_type(Channels::Telegram.key)
      scope = scope.where(tenant_id:) if tenant_id.present?

      scope.find_by(id: channel_id)
    end

    def error_message
      "Sorry, an error occurred. Please try again later."
    end
  end
end
