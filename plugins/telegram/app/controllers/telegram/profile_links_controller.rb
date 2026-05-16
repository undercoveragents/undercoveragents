# frozen_string_literal: true

module Telegram
  class ProfileLinksController < ApplicationController
    before_action :set_channel

    def create
      raw_token = Channels::TelegramLinkRequest.issue!(channel: @channel, user: current_user)
      flash[:telegram_link_tokens] = pending_tokens.merge(@channel.id.to_s => raw_token)

      redirect_to profile_path, notice: t("profile.telegram_token_generated", channel: @channel.name)
    rescue StandardError => e
      redirect_to profile_path, alert: e.message
    end

    def destroy
      @channel.channel_identities.where(user: current_user).destroy_all
      Channels::TelegramLinkRequest.clear_for(channel: @channel, user: current_user)

      redirect_to profile_path, notice: t("profile.telegram_unlinked", channel: @channel.name)
    end

    private

    def set_channel
      @channel = current_user.tenant.channels.by_type(Channels::Telegram.key).friendly.find(params.expect(:channel_id))
    end

    def pending_tokens
      flash[:telegram_link_tokens].is_a?(Hash) ? flash[:telegram_link_tokens] : {}
    end
  end
end
