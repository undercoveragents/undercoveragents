# frozen_string_literal: true

module Admin
  module Playground
    class MessagesController < BaseController
      include ChatUiSupport
      include PlaygroundAccess

      before_action :set_chat
      before_action :ensure_chat_accessible!

      def create
        enqueue_chat_message(chat: @chat, content: message_params[:content])
      end

      private

      def set_chat
        @chat = current_user.chats.find(params.expect(:chat_id))
      end

      def message_params
        params.expect(message: [:content])
      end

      def ensure_chat_accessible!
        return if playground_chat_accessible?(@chat)

        head :unprocessable_content
      end
    end
  end
end
