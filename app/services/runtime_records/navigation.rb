# frozen_string_literal: true

module RuntimeRecords
  class Navigation
    def self.broadcast!(chat:, path:)
      new(chat:, path:).broadcast!
    end

    def initialize(chat:, path:)
      @chat = chat
      @path = path
    end

    def broadcast!
      return :skipped unless @chat&.application? && @chat.user_id.present? && @path.present?

      ActionCable.server.broadcast(
        @chat.ui_stream_channel_name,
        @chat.ui_stream_payload(
          type: "navigate",
          chat_id: @chat.id,
          path: @path,
        ),
      )

      :broadcasted
    end
  end
end
