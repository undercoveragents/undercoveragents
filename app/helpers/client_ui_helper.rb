# frozen_string_literal: true

module ClientUiHelper
  def current_client_label(key)
    label_key = key.to_s
    client_settings = resolved_current_client_settings

    client_settings&.dig(:labels, label_key).presence || default_client_labels(client_settings).fetch(label_key)
  end

  def client_chat_delete_button_data
    {
      controller: "confirm",
      confirm_title_value: current_client_label(:delete_chat_confirm_title),
      confirm_message_value: current_client_label(:delete_chat_confirm_message),
      confirm_confirm_label_value: current_client_label(:delete_chat_confirm_label),
      confirm_confirm_icon_value: "fa-solid fa-trash",
      confirm_confirm_style_value: "danger",
    }
  end

  private

  def default_client_labels(client_settings = resolved_current_client_settings)
    Channels::Client.default_labels(channel_name: client_settings&.dig(:name))
  end

  def resolved_current_client_settings
    return current_client if respond_to?(:current_client, true)

    nil
  end
end
