# frozen_string_literal: true

module ClientUiHelper
  def current_client_label(key)
    label_key = key.to_s
    client_settings = resolved_current_client_settings

    client_settings&.dig(:labels, label_key).presence || default_client_labels(client_settings).fetch(label_key)
  end

  def current_client_message_actions
    client_settings = resolved_current_client_settings
    raw_actions = if client_settings.is_a?(Hash)
                    client_settings[:message_actions] || client_settings["message_actions"] || {}
                  else
                    {}
                  end

    default_actions = Channels::Client.normalized_message_actions_payload({})

    if raw_actions.is_a?(Hash) && (raw_actions.key?(:visibility) || raw_actions.key?("visibility"))
      return default_actions.merge(
        raw_actions.deep_stringify_keys.slice(
          "visibility",
          "copy_assistant_response",
          "copy_user_message",
          "assistant_feedback",
          "retry_assistant_message",
        ),
      )
    end

    Channels::Client.normalized_message_actions_payload(raw_actions)
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
