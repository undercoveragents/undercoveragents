# frozen_string_literal: true

module ChatUiHelper
  include ClientChatPathsHelper
  include ChatDisplayHelper
  include ChatMessageActionsHelper
  include ChatReferenceUiHelper
  include ClientUiHelper

  ChatComponentConfig = Data.define(
    :variant,
    :container_class,
    :placeholder,
    :empty_state_title,
    :empty_state_body,
    :empty_state_icon,
    :allow_attachments,
    :allow_drag_drop,
    :attachment_accept,
    :attach_label,
    :send_label,
    :stop_label,
    :drop_label,
    :reference_config,
    :message_actions,
    :thinking_level_selector_visible,
    :thinking_level_label,
    :thinking_level_options,
  ) do
    def root_classes
      [
        container_class,
        "shared-chat",
        "shared-chat--#{variant}",
        "shared-chat--message-actions-#{message_actions.visibility}",
      ].compact.join(" ")
    end

    def allow_attachments?
      allow_attachments
    end

    def allow_drag_drop?
      allow_attachments? && allow_drag_drop
    end

    def with_attachment_model(model_record)
      effective_accept = model_record&.attachment_accept
      effective_allow_attachments = allow_attachments && effective_accept.present?
      effective_thinking_level_selector_visible =
        thinking_level_selector_visible && model_record&.supports_reasoning? != false

      self.class.new(
        **to_h,
        allow_attachments: effective_allow_attachments,
        allow_drag_drop: effective_allow_attachments && allow_drag_drop,
        attachment_accept: effective_accept,
        thinking_level_selector_visible: effective_thinking_level_selector_visible,
      )
    end

    def references_enabled?
      reference_config.enabled?
    end

    def message_actions_for?(message)
      message_actions.enabled_for?(message.role)
    end

    def thinking_level_selector_visible?
      thinking_level_selector_visible
    end
  end

  def build_chat_component(
    variant:,
    agent_name: nil,
    allow_attachments: true,
    allow_drag_drop: nil,
    references: nil
  )
    case variant.to_sym
    when :playground
      build_playground_chat_component(agent_name:, allow_attachments:, allow_drag_drop:, references:)
    when :application then build_application_chat_component(allow_attachments:, allow_drag_drop:, references:)
    when :client then build_client_chat_component(allow_attachments:, allow_drag_drop:, references:)
    else
      raise ArgumentError, "Unknown chat component variant: #{variant}"
    end
  end

  def chat_input_data(component = nil)
    data = {
      chat_target: "input",
      action: "input->chat#resizeInput keydown->chat#handleKeydown",
    }

    chat_input_reference_data(data, component)
  end

  def chat_shell_root_data(chat, cancel_url, poll_url, component)
    data = {
      controller: chat_shell_controllers(component),
      chat_chat_id_value: chat.id,
      chat_cancel_url_value: cancel_url,
      chat_poll_url_value: poll_url,
      action: "human-in-the-loop-tool-call:submitted->chat#submitHumanInTheLoopAnswers " \
              "human-in-the-loop-tool-call:failed->chat#rollbackHumanInTheLoopAnswers",
    }

    data = chat_reference_root_data(data, component)

    data[:chat_stream_stream_token_value] = chat.signed_ui_stream_name unless component.variant == :application
    if component.allow_attachments? && component.attachment_accept.present?
      data[:chat_attachment_accept_value] = component.attachment_accept
    end

    return data unless component.allow_drag_drop?

    data.merge(
      chat_target: "dropZone",
      action: "#{data[:action]} dragenter->chat#dragEnter dragover->chat#dragOver " \
              "dragleave->chat#dragLeave drop->chat#drop",
    )
  end

  def build_playground_chat_component(agent_name:, allow_attachments:, allow_drag_drop:, references:)
    chat_component_config(
      variant: :playground,
      container_class: "playground-chat-area",
      placeholder: "Type your message…",
      empty_state_title: "Start a conversation",
      empty_state_body: "Type a message below to begin chatting with #{agent_name.presence || "the agent"}.",
      allow_attachments:,
      allow_drag_drop: allow_drag_drop.nil? ? allow_attachments : allow_drag_drop,
      reference_config: references || chat_reference_config,
      message_actions: default_message_actions_config,
    )
  end

  def build_application_chat_component(allow_attachments:, allow_drag_drop:, references:)
    chat_component_config(
      variant: :application,
      container_class: "ms-chat-panel",
      placeholder: "Ask to Agent Alpha… (type # to reference something)",
      empty_state_title: nil,
      empty_state_body: "Ask me anything.",
      allow_attachments:,
      allow_drag_drop: allow_drag_drop.nil? ? false : allow_drag_drop,
      reference_config: references || chat_reference_config,
      message_actions: default_message_actions_config,
      thinking_level_selector_visible: true,
    )
  end

  def build_client_chat_component(allow_attachments:, allow_drag_drop:, references:)
    chat_component_config(
      variant: :client,
      container_class: "chat-container",
      placeholder: current_client_label(:composer_placeholder),
      empty_state_title: current_client_label(:empty_state_title),
      empty_state_body: current_client_label(:empty_state_body),
      attach_label: current_client_label(:attach_button_label),
      send_label: current_client_label(:send_button_label),
      stop_label: current_client_label(:stop_button_label),
      drop_label: current_client_label(:drop_files_label),
      allow_attachments:,
      allow_drag_drop: allow_drag_drop.nil? ? allow_attachments : allow_drag_drop,
      reference_config: references || chat_reference_config,
      message_actions: current_client_message_actions_config,
      thinking_level_selector_visible: current_client_thinking_level_selector_enabled?,
    )
  end

  def chat_component_config(**attributes)
    ChatComponentConfig.new(
      empty_state_icon: "fa-solid fa-comments",
      attach_label: "Attach",
      attachment_accept: nil,
      send_label: "Send",
      stop_label: "Stop",
      drop_label: "Drop files here",
      message_actions: default_message_actions_config,
      thinking_level_selector_visible: false,
      thinking_level_label: "Thinking level",
      thinking_level_options: LlmConfigHelper::THINKING_EFFORT_OPTIONS,
      **attributes,
    )
  end
end
