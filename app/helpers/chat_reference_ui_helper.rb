# frozen_string_literal: true

module ChatReferenceUiHelper
  ChatReferenceConfig = Data.define(:enabled, :search_url, :trigger, :input_name, :kinds) do
    def enabled? = enabled && search_url.present?

    def kinds_value = Array(kinds).join(",")
  end

  def chat_reference_config(enabled: false, search_url: nil, trigger: "#", input_name: "message[references]", kinds: [])
    ChatReferenceConfig.new(enabled:, search_url:, trigger:, input_name:, kinds:)
  end

  def chat_input_reference_data(data, component)
    return data unless component&.references_enabled?

    data.merge(
      chat_references_target: "input",
      action: "input->chat#resizeInput input->chat-references#input " \
              "keydown->chat-references#keydown keydown->chat#handleKeydown",
    )
  end

  def chat_reference_root_data(data, component)
    return data unless component.references_enabled?

    data.merge(
      chat_references_url_value: component.reference_config.search_url,
      chat_references_trigger_value: component.reference_config.trigger,
      chat_references_kinds_value: component.reference_config.kinds_value,
    )
  end

  def chat_shell_controllers(component)
    controllers = ["chat"]
    controllers << "chat-stream" unless component.variant == :application
    controllers << "chat-references" if component.references_enabled?
    controllers.join(" ")
  end
end
