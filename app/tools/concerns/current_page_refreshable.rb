# frozen_string_literal: true

module CurrentPageRefreshable
  private

  def broadcast_current_page_refresh?
    chat = refreshable_chat
    path = current_page_path
    return false unless chat && path

    ActionCable.server.broadcast(
      chat.ui_stream_channel_name,
      refresh_payload(chat, path),
    )

    true
  end

  def refreshable_chat
    chat = @runtime_context&.chat
    return unless chat&.application? && chat.user_id.present?

    chat
  end

  def current_page_path
    @runtime_context&.ui_context&.dig("page", "path").to_s.presence
  end

  def refresh_payload(chat, path)
    chat.ui_stream_payload(
      type: "refresh",
      chat_id: chat.id,
      path:,
      current_path: path,
    )
  end
end
