# frozen_string_literal: true

module Telegram
  class WebhookSetupService
    include Rails.application.routes.url_helpers

    Result = Data.define(:success?, :message)

    def initialize(channel, host: nil)
      @channel = channel
      @host = host
    end

    def call
      return failure(I18n.t("channels.telegram.not_telegram")) unless telegram_channel?

      secret = connector.webhook_secret.presence || SecureRandom.hex(32)
      webhook_url = build_webhook_url(secret)
      connector.register_webhook!(webhook_url, secret:)
      connector.save!

      Result.new(success?: true, message: I18n.t("channels.telegram.webhook_registered"))
    rescue StandardError => e
      failure(I18n.t("channels.telegram.webhook_failed", error: e.message))
    end

    private

    attr_reader :channel

    def connector
      channel.connector
    end

    def telegram_channel?
      channel.channel_type == Channels::Telegram.key && connector&.connector_type == "telegram"
    end

    def build_webhook_url(secret)
      if ENV["TELEGRAM_WEBHOOK_BASE_URL"].present?
        "#{ENV["TELEGRAM_WEBHOOK_BASE_URL"].chomp("/")}/channels/telegram/#{channel.to_param}/webhook/#{secret}"
      else
        telegram_channel_webhook_url(channel_id: channel.to_param, token: secret, host: @host)
      end
    end

    def failure(message)
      Result.new(success?: false, message:)
    end
  end
end
