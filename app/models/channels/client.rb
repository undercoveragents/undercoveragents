# frozen_string_literal: true

module Channels
  class Client
    include UndercoverAgents::PluginSystem::Configurator
    include ChannelPlugin

    CONTENT_FIELDS = ClientConfiguration::CONTENT_FIELDS
    LABEL_FIELDS = ClientConfiguration::LABEL_FIELDS
    MESSAGE_ACTION_FIELDS = ClientConfiguration::MESSAGE_ACTION_FIELDS
    MESSAGE_ACTION_BOOLEAN_FIELDS = ClientConfiguration::MESSAGE_ACTION_BOOLEAN_FIELDS
    MESSAGE_ACTION_VISIBILITY_VALUES = ClientConfiguration::MESSAGE_ACTION_VISIBILITY_VALUES
    LABEL_LENGTH_LIMIT = ClientConfiguration::LABEL_LENGTH_LIMIT
    ALLOWED_TAGS = [
      "p", "br", "strong", "em", "b", "i", "u", "s", "a", "ul", "ol", "li",
      "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "code", "pre", "span", "sub", "sup",
    ].freeze
    ALLOWED_ATTRIBUTES = ["href", "target", "rel", "class"].freeze

    CONTENT_FIELDS.each do |field_name|
      attribute field_name, :string
    end

    LABEL_FIELDS.each do |field_name|
      attribute field_name, :string
    end

    MESSAGE_ACTION_FIELDS.each do |field_name|
      if MESSAGE_ACTION_BOOLEAN_FIELDS.include?(field_name)
        attribute field_name, :boolean
      else
        attribute field_name, :string
      end
    end

    validates :title, length: { maximum: 5000 }
    validates :welcome_message, length: { maximum: 10_000 }
    validates :footer, length: { maximum: 5000 }
    validate :label_lengths
    validate :message_action_visibility_value
    before_validation :sanitize_rich_fields

    key "client"
    label "Client"
    icon "fa-solid fa-comments"
    description "Publish a branded web chat experience backed by an agent."
    target_kinds ["agent"]

    def self.permitted_params(params)
      params.fetch(:channel, ActionController::Parameters.new)
            .permit(:title, :welcome_message, :footer, *LABEL_FIELDS, *MESSAGE_ACTION_FIELDS)
    end

    def self.default_labels(channel_name: nil)
      ClientConfiguration::STATIC_LABEL_DEFAULTS.merge(
        "welcome_heading" => "Welcome to #{channel_name.presence || APP_NAME}",
      )
    end

    def self.default_message_actions_payload
      ClientConfiguration.default_message_actions_payload
    end

    def self.normalized_message_actions_payload(settings)
      ClientConfiguration.normalized_message_actions_payload(settings)
    end

    def summary
      "Web chat"
    end

    def form_partial_path
      Rails.root.join("app/views/channels/client")
    end

    def show_partial_path
      form_partial_path
    end

    def effective_label_settings(channel_name:)
      self.class.default_labels(channel_name:).merge(label_overrides)
    end

    def settings_payload(channel:)
      agent = channel.client_agent
      logo_url = if channel.logo.attached?
                   Rails.application.routes.url_helpers.rails_blob_path(channel.logo, only_path: true)
                 end
      message_action_settings = effective_message_action_settings

      {
        id: channel.id,
        name: channel.name,
        title:,
        welcome_message:,
        footer:,
        labels: effective_label_settings(channel_name: channel.name),
        **message_action_payload_attributes(message_action_settings),
        agent_id: agent&.id,
        agent_name: agent&.name,
        logo_url:,
      }
    end

    private

    def label_lengths
      label_overrides.each do |key, value|
        next if value.blank? || value.to_s.length <= LABEL_LENGTH_LIMIT

        errors.add("labels.#{key}", "is too long (maximum is #{LABEL_LENGTH_LIMIT} characters)")
      end
    end

    def label_overrides
      LABEL_FIELDS.each_with_object({}) do |field_name, overrides|
        value = public_send(field_name)
        overrides[field_name.to_s] = value if value.present?
      end
    end

    def effective_message_action_settings
      self.class.default_message_actions_payload.merge(message_action_overrides)
    end

    def sanitize_rich_fields
      sanitizer = Rails::HTML5::SafeListSanitizer.new

      CONTENT_FIELDS.each do |field_name|
        value = public_send(field_name)
        next if value.blank?

        public_send(
          "#{field_name}=",
          sanitizer.sanitize(value, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES),
        )
      end
    end

    def message_action_visibility_value
      value = effective_message_action_settings["message_actions_visibility"]
      return if MESSAGE_ACTION_VISIBILITY_VALUES.include?(value)

      errors.add(
        :message_actions_visibility,
        "must be one of: #{MESSAGE_ACTION_VISIBILITY_VALUES.join(", ")}",
      )
    end

    def message_action_overrides
      MESSAGE_ACTION_FIELDS.each_with_object({}) do |field_name, overrides|
        value = public_send(field_name)
        next if value.nil?

        overrides[field_name.to_s] = value
      end
    end

    def message_action_payload_attributes(settings)
      {
        message_actions: self.class.normalized_message_actions_payload(settings),
        message_actions_visibility: settings["message_actions_visibility"],
        copy_assistant_response_enabled: settings["copy_assistant_response_enabled"],
        copy_user_message_enabled: settings["copy_user_message_enabled"],
        assistant_feedback_enabled: settings["assistant_feedback_enabled"],
        retry_assistant_message_enabled: settings["retry_assistant_message_enabled"],
      }
    end
  end
end
