# frozen_string_literal: true

module Admin
  module Playground
    class MessagesController < BaseController
      include ChatUiSupport
      include PlaygroundAccess

      before_action :set_chat
      before_action :ensure_chat_accessible!
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

      def set_chat
        @chat = current_user.chats.find(params[:chat_id] || params.expect(:id))
      end

      def message_params
        params.expect(message: [:content])
      end

      def set_message
        @message = @chat.messages.visible.find(params.expect(:message_id))
      end

      def feedback_params
        params.expect(feedback: [:value, :category, :comment])
      end

      def ensure_chat_accessible!
        return if playground_chat_accessible?(@chat)

        head :unprocessable_content
      end
    end
  end
end
