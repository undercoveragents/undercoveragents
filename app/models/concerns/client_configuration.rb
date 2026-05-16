# frozen_string_literal: true

module ClientConfiguration
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
  CONFIGURATION_ATTRIBUTE_NAMES = (CONTENT_FIELDS + LABEL_FIELDS).freeze
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

  included do
    before_validation :ensure_client_configuration

    validates :title, length: { maximum: 5000 }
    validates :welcome_message, length: { maximum: 10_000 }
    validates :footer, length: { maximum: 5000 }

    validate :validate_client_label_lengths
  end

  class_methods do
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

  def effective_label_settings
    self.class.default_labels(client_name: name).merge(present_label_overrides)
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

  def content_configuration
    configuration_section("content")
  end

  def label_configuration
    configuration_section("labels")
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

  def write_content_configuration(field_name, value)
    update_configuration_section("content", field_name, value, remove_blank: false)
  end

  def write_label_configuration(field_name, value)
    update_configuration_section("labels", field_name, value, remove_blank: true)
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
end
