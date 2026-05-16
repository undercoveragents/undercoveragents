# frozen_string_literal: true

module ClientChatPathsHelper
  def admin_client_preview_page_path(client: current_client_record, chat: nil)
    return root_path unless client

    options = { view: :preview }
    options[:chat_id] = chat.id if chat
    admin_channel_path(client, options)
  end

  def client_chat_brand_url(client: current_client_record)
    return admin_client_preview_page_path(client:) if admin_client_preview? && client

    root_path
  end

  def client_chat_new_path(client: current_client_record)
    return chats_path(client_chat_preview_params(client:)) if admin_client_preview? && client

    chats_path
  end

  def client_chat_sidebar_link_path(chat, client: current_client_record)
    return admin_client_preview_page_path(client: client || chat.channel, chat:) if admin_client_preview?

    chat_path(chat)
  end

  def client_chat_sidebar_link_data
    return { turbo_frame: "app-content-frame" } if admin_client_preview?

    {}
  end

  def client_chat_delete_path(chat, client: current_client_record)
    return chat_path(chat, client_chat_preview_params(client: client || chat.channel)) if admin_client_preview?

    chat_path(chat)
  end

  def client_chat_more_path(page:, client: current_client_record, format: :turbo_stream)
    if admin_client_preview? && client
      return more_chats_path(client_chat_preview_params(client:, extra: { page:, format: }))
    end

    more_chats_path(page:, format:)
  end

  def client_chat_message_path(chat, client: current_client_record)
    return chat_messages_path(chat, client_chat_preview_params(client: client || chat.channel)) if admin_client_preview?

    chat_messages_path(chat)
  end

  def client_chat_cancel_path(chat, client: current_client_record)
    return cancel_chat_path(chat, client_chat_preview_params(client: client || chat.channel)) if admin_client_preview?

    cancel_chat_path(chat)
  end

  def client_chat_poll_path(chat, client: current_client_record)
    if admin_client_preview?
      return chat_path(
        chat,
        client_chat_preview_params(client: client || chat.channel, extra: { format: :turbo_stream }),
      )
    end

    chat_path(chat, format: :turbo_stream)
  end

  private

  def client_chat_preview_params(client:, extra: {})
    return extra unless admin_client_preview? && client

    { preview_channel_id: client.to_param, admin_preview: true }.merge(extra)
  end
end
