# frozen_string_literal: true

module ToolCalls
  class Presentation
    RUNNING_MODES = ["random", "rotate"].freeze
    DEFAULT_RUNNING_MODE = "random"
    DEFAULT_RUNNING_INTERVAL_MS = 2200
    MIN_RUNNING_INTERVAL_MS = 800
    MAX_RUNNING_INTERVAL_MS = 10_000
    MAX_MESSAGE_COUNT = 50
    MAX_MESSAGE_LENGTH = 120
    MAX_GROUP_TITLE_LENGTH = 120
    ICON_PATTERN = /\Afa-(solid|regular|brands)\sfa-[a-z0-9-]+\z/
    ICON_ALIASES = {
      "fa-solid fa-sparkles" => "fa-solid fa-wand-magic-sparkles",
    }.freeze

    attr_reader :complete_messages,
                :display_name,
                :group_title,
                :icon,
                :running_interval_ms,
                :running_messages,
                :running_mode

    def self.normalize_icon_input(value)
      normalized = value.to_s.squish.presence
      ICON_ALIASES.fetch(normalized, normalized)
    end

    def self.valid_icon?(value)
      normalized = normalize_icon_input(value)
      normalized.blank? || normalized.match?(ICON_PATTERN)
    end

    def self.sanitize_icon(value)
      normalized = normalize_icon_input(value)
      normalized if valid_icon?(normalized)
    end

    def self.normalize_messages(values)
      Array(values)
        .flatten
        .filter_map { |value| value.to_s.squish.presence }
        .uniq
        .first(MAX_MESSAGE_COUNT)
    end

    def self.parse_message_text(value)
      value.to_s.lines.map(&:strip).compact_blank.uniq
    end

    def self.normalize_group_title(value)
      value.to_s.squish.presence&.slice(0, MAX_GROUP_TITLE_LENGTH)
    end

    def self.normalize_running_mode(value)
      normalized = value.to_s.presence || DEFAULT_RUNNING_MODE
      RUNNING_MODES.include?(normalized) ? normalized : DEFAULT_RUNNING_MODE
    end

    def self.normalize_interval(value)
      integer = Integer(value, exception: false)
      integer = DEFAULT_RUNNING_INTERVAL_MS if integer.nil?
      integer.clamp(MIN_RUNNING_INTERVAL_MS, MAX_RUNNING_INTERVAL_MS)
    end

    def initialize(display_name:, icon:, **options)
      @display_name = display_name.to_s
      @icon = self.class.sanitize_icon(icon)
      @running_messages = self.class.normalize_messages(options.fetch(:running_messages, []))
      @running_mode = self.class.normalize_running_mode(options.fetch(:running_mode, DEFAULT_RUNNING_MODE))
      @running_interval_ms = self.class.normalize_interval(
        options.fetch(:running_interval_ms, DEFAULT_RUNNING_INTERVAL_MS),
      )
      @complete_messages = self.class.normalize_messages(options.fetch(:complete_messages, []))
      @group_title = self.class.normalize_group_title(options[:group_title])
    end

    def merge(overrides)
      with(
        display_name: merged_value(overrides.display_name, display_name),
        icon: merged_value(overrides.icon, icon),
        running_messages: merged_value(overrides.running_messages, running_messages),
        running_mode: merged_value(overrides.running_mode, running_mode),
        running_interval_ms: merged_value(overrides.running_interval_ms, running_interval_ms),
        complete_messages: merged_value(overrides.complete_messages, complete_messages),
        group_title: merged_value(overrides.group_title, group_title),
      )
    end

    def with(**overrides)
      self.class.new(
        display_name: overrides.fetch(:display_name, display_name),
        icon: overrides.fetch(:icon, icon),
        running_messages: overrides.fetch(:running_messages, running_messages),
        running_mode: overrides.fetch(:running_mode, running_mode),
        running_interval_ms: overrides.fetch(:running_interval_ms, running_interval_ms),
        complete_messages: overrides.fetch(:complete_messages, complete_messages),
        group_title: overrides.fetch(:group_title, group_title),
      )
    end

    def grouped?
      group_title.present?
    end

    def sample_phrase(status:, random: Random)
      messages = status.to_s == "running" ? running_messages : complete_messages
      messages.sample(random:) || ""
    end

    def widget_payload(status:, phrase: nil)
      {
        tool_widget_status_value: status,
        tool_widget_running_messages_value: running_messages.to_json,
        tool_widget_running_mode_value: running_mode,
        tool_widget_running_interval_ms_value: running_interval_ms,
        tool_widget_complete_messages_value: complete_messages.to_json,
        tool_widget_initial_phrase_value: phrase.presence,
        tool_widget_group_title_value: group_title,
      }.compact
    end

    private

    def merged_value(value, fallback)
      value.presence || fallback
    end
  end
end
