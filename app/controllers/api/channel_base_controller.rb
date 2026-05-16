# frozen_string_literal: true

module Api
  class ChannelBaseController < BaseController
    private

    attr_reader :current_channel, :current_channel_credential

    def require_api_authentication
      @current_channel = Channel.enabled.friendly.find(params.expect(:channel_slug))

      token = extract_bearer_token
      @current_channel_credential = ChannelCredential.authenticate(token, channel: @current_channel)

      render_unauthorized unless @current_channel_credential
    rescue ActiveRecord::RecordNotFound
      render_not_found("Channel not found")
    end
  end
end
