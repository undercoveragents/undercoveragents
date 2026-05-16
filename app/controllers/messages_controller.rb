# frozen_string_literal: true

class MessagesController < ApplicationController
  include ChatUiSupport

  before_action :authorize_preview_client, if: :admin_client_preview?
  before_action :set_chat

  def create
    enqueue_chat_message(chat: @chat, content: message_params[:content])
  end

  private

  def authorize_preview_client
    authorize current_client_record, :show?
  end

  def set_chat
    @chat = user_chats_for_channel(channel: current_client_record).find(params.expect(:chat_id))
  end

  def message_params
    params.expect(message: [:content])
  end
end
