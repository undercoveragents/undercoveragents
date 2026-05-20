# frozen_string_literal: true

class MessagesController < ApplicationController
  include ChatUiSupport

  before_action :authorize_preview_client, if: :admin_client_preview?
  before_action :set_chat
  before_action :set_message, only: [:retry, :feedback]

  def create
    enqueue_chat_message(chat: @chat, content: message_params[:content])
  end

  def retry
    source_message = retry_source_message(chat: @chat, message: @message)
    return head :unprocessable_content if source_message.nil?

    enqueue_chat_message(
      chat: @chat,
      content: source_message.content,
      attachment_signed_ids: retry_attachment_signed_ids(source_message),
    )
  end

  def feedback
    feedback = persist_message_feedback(
      chat: @chat,
      message: @message,
      user: current_user,
      attributes: feedback_params.to_h,
    )

    if feedback.save
      head :no_content
    else
      render json: { errors: feedback.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def authorize_preview_client
    authorize current_client_record, :show?
  end

  def set_chat
    @chat = user_chats_for_channel(channel: current_client_record).find(params[:chat_id] || params.expect(:id))
  end

  def set_message
    @message = @chat.messages.visible.find(params.expect(:message_id))
  end

  def message_params
    params.expect(message: [:content])
  end

  def feedback_params
    params.expect(feedback: [:value, :category, :comment])
  end
end
