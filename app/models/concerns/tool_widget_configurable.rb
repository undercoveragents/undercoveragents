# frozen_string_literal: true

module ToolWidgetConfigurable
  extend ActiveSupport::Concern

  FORM_PARAM_KEYS = [
    :tool_widget_icon,
    :tool_widget_running_mode,
    :tool_widget_running_interval_ms,
    :tool_widget_running_messages_text,
    :tool_widget_complete_messages_text,
    :tool_compaction_policy,
  ].freeze
  DESIGNER_ATTRIBUTE_KEYS = FORM_PARAM_KEYS.map do |key|
    key.to_s.sub(/_messages_text\z/, "_messages")
  end.freeze

  def self.compaction_policy_values
    ["", *Chats::MessageCompactor::POLICIES.map(&:to_s)]
  end

  def self.normalize_compaction_policy(value)
    return "" if value.blank?

    candidate = value.to_s
    compaction_policy_values.include?(candidate) ? candidate : ""
  end

  def self.normalize_widget_params(raw)
    attrs = raw.to_h.symbolize_keys
    return raw unless widget_fields_submitted?(raw)

    normalize_icon_and_messages(attrs)
    normalize_running_behavior(attrs)
    attrs[:tool_compaction_policy] = normalize_compaction_policy(attrs[:tool_compaction_policy])
    ActionController::Parameters.new(attrs).permit!
  end

  def self.normalize_icon_and_messages(attrs)
    attrs[:tool_widget_icon] = ToolCalls::Presentation.normalize_icon_input(attrs[:tool_widget_icon])
    attrs[:tool_widget_running_messages] = ToolCalls::Presentation.parse_message_text(
      attrs.delete(:tool_widget_running_messages_text),
    )
    attrs[:tool_widget_complete_messages] = ToolCalls::Presentation.parse_message_text(
      attrs.delete(:tool_widget_complete_messages_text),
    )
  end

  def self.normalize_running_behavior(attrs)
    attrs[:tool_widget_running_mode] = ToolCalls::Presentation.normalize_running_mode(attrs[:tool_widget_running_mode])
    attrs[:tool_widget_running_interval_ms] = ToolCalls::Presentation.normalize_interval(
      attrs[:tool_widget_running_interval_ms],
    )
  end

  def self.widget_fields_submitted?(raw)
    submitted_keys = raw.to_h.keys.map(&:to_s)
    submitted_keys.intersect?(FORM_PARAM_KEYS.map(&:to_s))
  end

  included do
    attribute :tool_widget_icon, :string
    attribute :tool_widget_running_messages, default: -> { [] }
    attribute :tool_widget_running_mode, :string, default: ToolCalls::Presentation::DEFAULT_RUNNING_MODE
    attribute :tool_widget_running_interval_ms, :integer, default: ToolCalls::Presentation::DEFAULT_RUNNING_INTERVAL_MS
    attribute :tool_widget_complete_messages, default: -> { [] }
    attribute :tool_compaction_policy, :string, default: ""

    validates :tool_widget_icon, length: { maximum: 60 }, allow_blank: true
    validates :tool_widget_running_mode, inclusion: { in: ToolCalls::Presentation::RUNNING_MODES }
    validates :tool_widget_running_interval_ms,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: ToolCalls::Presentation::MIN_RUNNING_INTERVAL_MS,
                less_than_or_equal_to: ToolCalls::Presentation::MAX_RUNNING_INTERVAL_MS,
              }
    validates :tool_compaction_policy,
              inclusion: { in: ->(_) { ToolWidgetConfigurable.compaction_policy_values } },
              allow_nil: true

    validate :tool_widget_icon_must_be_font_awesome
    validate :tool_widget_messages_must_fit_limits
  end

  class_methods do
    def permit_params_with_widget(params, keys)
      raw = params.expect(type_key.to_sym => [*keys, *FORM_PARAM_KEYS])
      ToolWidgetConfigurable.normalize_widget_params(raw)
    end
  end

  def to_configuration
    strip_default_tool_widget_config(super)
  end

  def tool_widget_customized?
    tool_widget_icon.present? ||
      tool_widget_running_messages.present? ||
      tool_widget_complete_messages.present? ||
      tool_widget_running_mode != ToolCalls::Presentation::DEFAULT_RUNNING_MODE ||
      tool_widget_running_interval_ms != ToolCalls::Presentation::DEFAULT_RUNNING_INTERVAL_MS
  end

  def tool_widget_override_presentation(display_name:, icon:)
    ToolCalls::Presentation.new(
      display_name:,
      icon: tool_widget_icon.presence || icon,
      running_messages: tool_widget_running_messages,
      running_mode: tool_widget_running_mode,
      running_interval_ms: tool_widget_running_interval_ms,
      complete_messages: tool_widget_complete_messages,
    )
  end

  private

  def tool_widget_icon_must_be_font_awesome
    return if ToolCalls::Presentation.valid_icon?(tool_widget_icon)

    errors.add(:tool_widget_icon, "must be a valid Font Awesome class pair")
  end

  def tool_widget_messages_must_fit_limits
    validate_tool_widget_message_set(:tool_widget_running_messages)
    validate_tool_widget_message_set(:tool_widget_complete_messages)
  end

  def validate_tool_widget_message_set(attribute_name)
    messages = Array(public_send(attribute_name))
               .flatten
               .filter_map { |message| message.to_s.squish.presence }
               .uniq

    if messages.size > ToolCalls::Presentation::MAX_MESSAGE_COUNT
      errors.add(attribute_name, "must contain at most #{ToolCalls::Presentation::MAX_MESSAGE_COUNT} messages")
    end

    return unless messages.any? { |message| message.length > ToolCalls::Presentation::MAX_MESSAGE_LENGTH }

    errors.add(attribute_name, "messages must be #{ToolCalls::Presentation::MAX_MESSAGE_LENGTH} characters or fewer")
  end

  def strip_default_tool_widget_config(configuration)
    sanitized = configuration.dup
    strip_blank_widget_entries(sanitized)
    strip_default_running_behavior(sanitized)
    sanitized
  end

  def strip_blank_widget_entries(sanitized)
    sanitized.delete("tool_widget_icon") if sanitized["tool_widget_icon"].blank?
    sanitized.delete("tool_widget_group_enabled")
    sanitized.delete("tool_widget_group_title")

    sanitized.delete("tool_widget_running_messages") if Array(sanitized["tool_widget_running_messages"]).blank?
    sanitized.delete("tool_widget_complete_messages") if Array(sanitized["tool_widget_complete_messages"]).blank?
    sanitized.delete("tool_compaction_policy") if sanitized["tool_compaction_policy"].blank?
  end

  def strip_default_running_behavior(sanitized)
    running_mode = sanitized["tool_widget_running_mode"]
    interval = sanitized["tool_widget_running_interval_ms"]

    sanitized.delete("tool_widget_running_mode") if running_mode == ToolCalls::Presentation::DEFAULT_RUNNING_MODE

    return unless interval == ToolCalls::Presentation::DEFAULT_RUNNING_INTERVAL_MS ||
                  running_mode == ToolCalls::Presentation::DEFAULT_RUNNING_MODE

    sanitized.delete("tool_widget_running_interval_ms")
  end
end
