# frozen_string_literal: true

class MessagesController < ApplicationController
  include ChatUiSupport

  before_action :authorize_preview_client, if: :admin_client_preview?
  before_action :set_chat
  before_action :set_message, only: [:feedback]

  def create
    enqueue_chat_message(chat: @chat, content: message_params[:content], runtime_context: message_runtime_context)
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
    params.expect(message: [:content, :thinking_effort])
  end

  def message_runtime_context
    return {} unless current_client_thinking_level_selector_enabled?
    return {} unless chat_thinking_level_selector_supported?(@chat, model_record: chat_model_for_attachments(@chat))

    { llm_config: { thinking_effort: normalized_message_thinking_effort } }
  end

  def normalized_message_thinking_effort
    message_data = message_params.to_h.deep_stringify_keys
    return nil unless message_data.key?("thinking_effort")

    effort = message_data["thinking_effort"].to_s.presence || effective_chat_thinking_effort(@chat)
    return effort if Llm::ChatOptions::THINKING_EFFORTS.include?(effort)

    nil
  end

  def feedback_params
    params.expect(feedback: [:value, :category, :comment])
  end
end
