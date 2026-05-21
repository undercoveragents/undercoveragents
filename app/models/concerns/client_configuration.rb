# frozen_string_literal: true

module ClientConfiguration # rubocop:disable Metrics/ModuleLength
  extend ActiveSupport::Concern

  CONTENT_FIELDS = [:title, :welcome_message, :footer].freeze
  LABEL_FIELDS = [
    :new_chat_label,
    :sidebar_toggle_label,
    :sidebar_open_label,
    :composer_placeholder,
    :empty_state_title,
    :empty_state_body,
    :welcome_heading,
    :welcome_body,
    :no_agent_body,
    :attach_button_label,
    :send_button_label,
    :stop_button_label,
    :drop_files_label,
    :delete_chat_title,
    :delete_chat_confirm_title,
    :delete_chat_confirm_message,
    :delete_chat_confirm_label,
    :profile_settings_label,
    :admin_label,
    :change_password_label,
    :change_password_dialog_title,
    :theme_label,
    :sign_out_label,
  ].freeze
  MESSAGE_ACTION_BOOLEAN_FIELDS = [
    :copy_assistant_response_enabled,
    :copy_user_message_enabled,
    :assistant_feedback_enabled,
  ].freeze
  MESSAGE_ACTION_FIELDS = [
    :message_actions_visibility,
    *MESSAGE_ACTION_BOOLEAN_FIELDS,
  ].freeze
  MESSAGE_ACTION_VISIBILITY_VALUES = ["always", "hover"].freeze
  MESSAGE_ACTION_FIELD_NAMES = MESSAGE_ACTION_FIELDS.map(&:to_s).freeze
  CONFIGURATION_ATTRIBUTE_NAMES = (CONTENT_FIELDS + LABEL_FIELDS + MESSAGE_ACTION_FIELDS).freeze
  LABEL_LENGTH_LIMIT = 2_000
  STATIC_LABEL_DEFAULTS = {
    "new_chat_label" => "New chat",
    "sidebar_toggle_label" => "Toggle sidebar",
    "sidebar_open_label" => "Open sidebar",
    "composer_placeholder" => "Type your message…",
    "empty_state_title" => "Start a conversation",
    "empty_state_body" => "Type a message below to begin chatting.",
    "welcome_body" => "Start a conversation by typing a message below.",
    "no_agent_body" => "No agent is available yet. Please contact your administrator.",
    "attach_button_label" => "Attach",
    "send_button_label" => "Send",
    "stop_button_label" => "Stop",
    "drop_files_label" => "Drop files here",
    "delete_chat_title" => "Delete chat",
    "delete_chat_confirm_title" => "Delete Chat",
    "delete_chat_confirm_message" => "Are you sure you want to delete this chat?",
    "delete_chat_confirm_label" => "Delete",
    "profile_settings_label" => "Profile & Settings",
    "admin_label" => "Admin",
    "change_password_label" => "Change Password",
    "change_password_dialog_title" => "Change Password",
    "theme_label" => "Theme",
    "sign_out_label" => "Sign Out",
  }.freeze
  STATIC_MESSAGE_ACTION_DEFAULTS = {
    "message_actions_visibility" => "hover",
    "copy_assistant_response_enabled" => true,
    "copy_user_message_enabled" => true,
    "assistant_feedback_enabled" => true,
  }.freeze

  def self.default_message_actions_payload
    STATIC_MESSAGE_ACTION_DEFAULTS.deep_dup
  end

  def self.normalized_message_actions_payload(settings)
    action_settings = default_message_actions_payload.merge(settings.to_h.deep_stringify_keys)

    {
      "visibility" => action_settings.fetch("message_actions_visibility"),
      "copy_assistant_response" => action_settings.fetch("copy_assistant_response_enabled"),
      "copy_user_message" => action_settings.fetch("copy_user_message_enabled"),
      "assistant_feedback" => action_settings.fetch("assistant_feedback_enabled"),
    }
  end

  included do
    before_validation :ensure_client_configuration

    validates :title, length: { maximum: 5000 }
    validates :welcome_message, length: { maximum: 10_000 }
    validates :footer, length: { maximum: 5000 }

    validate :validate_client_label_lengths
    validate :validate_message_action_visibility
  end

  class_methods do
    delegate :default_message_actions_payload, :normalized_message_actions_payload, to: ClientConfiguration

    def configuration_attribute_names
      CONFIGURATION_ATTRIBUTE_NAMES
    end

    def default_labels(client_name: nil)
      STATIC_LABEL_DEFAULTS.merge("welcome_heading" => "Welcome to #{resolved_client_name(client_name)}")
    end

    private

    def resolved_client_name(client_name)
      client_name.presence || APP_NAME
    end
  end

  CONTENT_FIELDS.each do |field_name|
    define_method(field_name) do
      content_configuration[field_name.to_s]
    end

    define_method("#{field_name}=") do |value|
      write_content_configuration(field_name, value)
    end
  end

  LABEL_FIELDS.each do |field_name|
    define_method(field_name) do
      effective_label_settings.fetch(field_name.to_s)
    end

    define_method("#{field_name}=") do |value|
      write_label_configuration(field_name, value)
    end
  end

  MESSAGE_ACTION_FIELDS.each do |field_name|
    define_method(field_name) do
      effective_message_action_settings.fetch(field_name.to_s)
    end

    define_method("#{field_name}=") do |value|
      write_message_action_configuration(field_name, value)
    end
  end

  def effective_label_settings
    self.class.default_labels(client_name: name).merge(present_label_overrides)
  end

  def effective_message_action_settings
    self.class.default_message_actions_payload.merge(present_message_action_overrides)
  end

  private

  def ensure_client_configuration
    self.configuration = {} unless configuration.is_a?(Hash)
  end

  def validate_client_label_lengths
    LABEL_FIELDS.each do |field_name|
      value = public_send(field_name)
      next if value.blank? || value.length <= LABEL_LENGTH_LIMIT

      errors.add(field_name, "is too long (maximum is #{LABEL_LENGTH_LIMIT} characters)")
    end
  end

  def validate_message_action_visibility
    value = effective_message_action_settings["message_actions_visibility"]
    return if MESSAGE_ACTION_VISIBILITY_VALUES.include?(value)

    errors.add(:message_actions_visibility, "must be one of: #{MESSAGE_ACTION_VISIBILITY_VALUES.join(", ")}")
  end

  def content_configuration
    configuration_section("content")
  end

  def label_configuration
    configuration_section("labels")
  end

  def message_action_configuration
    configuration_section("message_actions")
  end

  def configuration_section(section_name)
    section = configuration_payload[section_name]
    section.is_a?(Hash) ? section : {}
  end

  def configuration_payload
    configuration.is_a?(Hash) ? configuration.deep_stringify_keys : {}
  end

  def present_label_overrides
    label_configuration.each_with_object({}) do |(key, value), labels|
      labels[key] = value if value.present?
    end
  end

  def present_message_action_overrides
    message_action_configuration.each_with_object({}) do |(key, value), settings|
      next unless persist_message_action_override?(key, value)

      settings[key] = value
    end
  end

  def write_content_configuration(field_name, value)
    update_configuration_section("content", field_name, value, remove_blank: false)
  end

  def write_label_configuration(field_name, value)
    update_configuration_section("labels", field_name, value, remove_blank: true)
  end

  def write_message_action_configuration(field_name, value)
    update_configuration_section("message_actions", field_name, value, remove_blank: false)
  end

  def update_configuration_section(section_name, field_name, value, remove_blank:)
    config = configuration_payload.deep_dup
    section = config[section_name].is_a?(Hash) ? config[section_name].deep_stringify_keys : {}
    key = field_name.to_s

    if value.nil? || (remove_blank && value.respond_to?(:blank?) && value.blank?)
      section.delete(key)
    else
      section[key] = value
    end

    config[section_name] = section
    self.configuration = config
  end

  def persist_message_action_override?(key, value)
    return false unless MESSAGE_ACTION_FIELD_NAMES.include?(key)
    return false if value.nil?
    return true unless value.respond_to?(:blank?)
    return true if value == false
    return true if value.present?

    key == "message_actions_visibility"
  end
end
