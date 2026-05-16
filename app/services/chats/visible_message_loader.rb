# frozen_string_literal: true

module Chats
  class VisibleMessageLoader
    def self.load(chat, include_attachments: false)
      new(chat, include_attachments:).load
    end

    def initialize(chat, include_attachments: false)
      @chat = chat
      @include_attachments = include_attachments
    end

    def load
      return [] unless chat

      messages = chat.messages.visible.order(:created_at, :id).to_a
      attach_chat_association(messages)
      preload_message_tool_calls(messages.select(&:assistant?))
      preload_message_attachments(messages.select(&:user?)) if include_attachments
      messages
    end

    private

    attr_reader :chat, :include_attachments

    def attach_chat_association(messages)
      messages.each do |message|
        message.association(:chat).tap do |association|
          association.target = chat
          association.loaded!
        end
      end
    end

    def preload_message_tool_calls(messages)
      return if messages.empty?

      ActiveRecord::Associations::Preloader.new(
        records: messages,
        associations: :tool_calls,
      ).call

      attach_message_association_to_tool_calls(messages)
    end

    def attach_message_association_to_tool_calls(messages)
      messages.each do |message|
        message.tool_calls.each do |tool_call|
          tool_call.association(:message).tap do |association|
            association.target = message
            association.loaded!
          end
        end
      end
    end

    def preload_message_attachments(messages)
      return if messages.empty?

      ActiveRecord::Associations::Preloader.new(
        records: messages,
        associations: { attachments_attachments: :blob },
      ).call
    end
  end
end
