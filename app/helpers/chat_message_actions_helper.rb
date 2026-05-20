# frozen_string_literal: true

module ChatMessageActionsHelper
  ChatMessageActionsConfig = Data.define(
    :visibility,
    :copy_assistant_response,
    :copy_user_message,
    :assistant_feedback,
    :retry_assistant_message,
  ) do
    def enabled_for?(role)
      case role.to_s
      when "assistant"
        copy_assistant_response || assistant_feedback || retry_assistant_message
      when "user"
        copy_user_message
      else
        false
      end
    end
  end

  def chat_message_retry_path(chat:, message:, component:)
    case component.variant
    when :application
      message_retry_admin_agent_alpha_path(message_id: message.id)
    when :playground
      message_retry_admin_playground_chat_path(chat, message_id: message.id)
    else
      message_retry_chat_path(chat, chat_message_action_path_options(chat:, message:))
    end
  end

  def chat_message_feedback_path(chat:, message:, component:)
    case component.variant
    when :application
      message_feedback_admin_agent_alpha_path(message_id: message.id)
    when :playground
      message_feedback_admin_playground_chat_path(chat, message_id: message.id)
    else
      message_feedback_chat_path(chat, chat_message_action_path_options(chat:, message:))
    end
  end

  def chat_message_copy_text(message)
    chat_message_display_content(message).to_s
  end

  def chat_message_feedback_categories
    MessageFeedback::NEGATIVE_CATEGORIES
  end

  def chat_message_actions_ui_context_selector(component)
    component.variant == :application ? "#admin-agent-alpha-page-context" : nil
  end

  private

  def default_message_actions_config
    build_message_actions_config(ClientConfiguration.normalized_message_actions_payload({}))
  end

  def current_client_message_actions_config
    build_message_actions_config(current_client_message_actions)
  end

  def build_message_actions_config(settings)
    normalized = settings.to_h.deep_symbolize_keys

    ChatMessageActionsConfig.new(
      visibility: normalized.fetch(:visibility, "hover"),
      copy_assistant_response: normalized.fetch(:copy_assistant_response, true),
      copy_user_message: normalized.fetch(:copy_user_message, true),
      assistant_feedback: normalized.fetch(:assistant_feedback, false),
      retry_assistant_message: normalized.fetch(:retry_assistant_message, true),
    )
  end

  def chat_message_action_path_options(chat:, message:)
    path_options = { message_id: message.id }
    return path_options unless respond_to?(:admin_client_preview?) && admin_client_preview?

    path_options.merge(client_chat_preview_params(client: current_client_record || chat.channel))
  end
end
