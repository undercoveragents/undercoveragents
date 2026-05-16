# frozen_string_literal: true

module Admin
  module ChannelPreviewRendering
    extend ActiveSupport::Concern

    private

    def client_preview_request?
      @channel.client_channel? && params[:view] == "preview"
    end

    def render_preview
      @chat = resolve_preview_chat
      @pagy_chats, @chats = pagy(:countless, preview_scoped_chats.recent, limit: 20)
      render_chat_surface(chat: @chat, component: build_chat_component(variant: :client))
      render :preview
    end

    def resolve_preview_chat
      if params[:chat_id].present?
        preview_scoped_chats.find(params.expect(:chat_id))
      else
        preview_scoped_chats.recent.first || build_preview_chat.tap(&:save!)
      end
    end

    def preview_scoped_chats
      user_chats_for_channel(channel: @channel)
    end

    def build_preview_chat
      build_user_chat(agent: @channel.client_agent, channel: @channel)
    end
  end
end
