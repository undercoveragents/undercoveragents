# frozen_string_literal: true

module Channels
  class Telegram
    include UndercoverAgents::PluginSystem::Configurator
    include ChannelPlugin

    DEFAULT_WELCOME_MESSAGE = "Hello from the bot!"
    DEFAULT_MAX_HISTORY = 50

    attribute :welcome_message, :string, default: DEFAULT_WELCOME_MESSAGE
    attribute :max_history_messages, :integer, default: DEFAULT_MAX_HISTORY
    attribute :streaming_enabled, :boolean, default: true

    key "telegram"
    label "Telegram"
    icon "fa-brands fa-telegram"
    description "Expose an agent through a Telegram channel."
    target_kinds ["agent"]
    requires_connector_type "telegram"

    validates :welcome_message, presence: true, length: { maximum: 2000 }
    validates :max_history_messages,
              numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 500 }
    validate :connector_present
    validate :connector_not_reused

    def self.permitted_params(params)
      params.fetch(:channel, ActionController::Parameters.new)
            .permit(:welcome_message, :max_history_messages, :streaming_enabled)
    end

    def summary
      parts = []
      parts << "@#{telegram_connector.bot_username}" if telegram_connector&.bot_username.present?
      parts << (streaming_enabled ? "Streaming" : "Final only")
      parts.join(" / ")
    end

    def form_partial_path
      File.expand_path("../../views/channels_telegram", __dir__)
    end

    def show_partial_path
      form_partial_path
    end

    def telegram_connector
      _channel_record&.connector
    end

    private

    def connector_present
      return if telegram_connector.present?

      errors.add(:connector, "is required")
    end

    def connector_not_reused
      channel_record = _channel_record
      connector_id = channel_record&.connector_id
      return if connector_id.blank?

      scope = Channel.where(channel_type: self.class.key, connector_id:)
      scope = scope.where.not(id: channel_record.id) if persisted_channel_record?(channel_record)
      return unless scope.exists?

      errors.add(:connector, "is already assigned to another Telegram channel")
    end

    def persisted_channel_record?(channel_record)
      return false unless channel_record

      channel_record.persisted?
    end
  end
end
