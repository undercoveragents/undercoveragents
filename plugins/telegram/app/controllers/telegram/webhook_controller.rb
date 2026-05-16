# frozen_string_literal: true

module Telegram
  class WebhookController < ApplicationController
    skip_before_action :require_authentication
    skip_before_action :verify_authenticity_token

    rescue_from ActionDispatch::Http::Parameters::ParseError, with: :handle_bad_request

    before_action :set_channel
    before_action :verify_webhook_secret

    def receive
      update = ::Telegram::Bot::Types::Update.new(request.request_parameters.presence || JSON.parse(request.body.read))
      message = update.message

      return head :ok unless message

      Telegram::ProcessMessageJob.perform_later(
        channel_id: @channel.id,
        tenant_id: @channel.tenant_id,
        telegram_chat_id: message.chat.id,
        telegram_user_id: message.from.id,
        telegram_username: message.from.username,
        text: message.text,
        photo: extract_photo(message),
      )

      head :ok
    rescue JSON::ParserError, ActionDispatch::Http::Parameters::ParseError
      head :bad_request
    end

    private

    def set_channel
      @channel = Channel.enabled.by_type(Channels::Telegram.key).friendly.find(params.expect(:channel_id))
    end

    def verify_webhook_secret
      secret = @channel.connector&.webhook_secret.to_s
      token = params.expect(:token).to_s

      return if secret.present? && token.present? && ActiveSupport::SecurityUtils.secure_compare(secret, token)

      head :unauthorized
      nil
    end

    def extract_photo(message)
      return nil unless message.respond_to?(:photo) && message.photo.is_a?(Array) && message.photo.any?

      largest_photo = message.photo.last
      {
        file_id: largest_photo.file_id,
        caption: message.respond_to?(:caption) ? message.caption : nil,
      }
    end

    def handle_bad_request
      head :bad_request
    end
  end
end
