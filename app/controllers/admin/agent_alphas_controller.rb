# frozen_string_literal: true

module Admin
  class AgentAlphasController < BaseController
    include ChatUiSupport
    include AgentAlphaSupport

    layout false

    def show
      @chats = agent_alpha_chats

      if params[:history].present?
        render :history
      elsif !agent_alpha_configured?
        render :unconfigured
      else
        @chat = agent_alpha_chat
        render_chat_surface(chat: @chat, component: agent_alpha_chat_component)
      end
    end

    def cancel
      chat = agent_alpha_chats.find_by(id: params[:chat_id])
      return head :ok unless chat

      chat.stop_stream!
      render_chat_status(chat:)
    end

    private

    def agent_alpha_chat_component
      build_chat_component(
        variant: :application,
        agent_name: agent_alpha_display_name,
        allow_attachments: true,
        allow_drag_drop: true,
        references: chat_reference_config(
          enabled: true,
          search_url: references_admin_agent_alpha_path,
          kinds: agent_alpha_reference_kinds,
        ),
      )
    end
  end
end
