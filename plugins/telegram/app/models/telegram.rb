# frozen_string_literal: true

module Connectors
  class Telegram
    include UndercoverAgents::PluginSystem::Configurator
    include ConnectorPlugin

    SENSITIVE_FIELDS = [:bot_token].freeze

    key "telegram"
    label "Telegram"
    icon "fa-brands fa-telegram"
    description "Send and receive messages via Telegram."
    sensitive_keys SENSITIVE_FIELDS

    # ── Attributes ─────────────────────────────────────────────────────────

    attribute :bot_token, :string
    attribute :bot_username, :string
    attribute :webhook_secret, :string
    attribute :webhook_url, :string

    # ── Validations ────────────────────────────────────────────────────────

    validates :bot_token, presence: true
    validate :webhook_secret_uniqueness

    # ── Class Methods ──────────────────────────────────────────────────────

    def self.permitted_params(params)
      params.expect(telegram: [:bot_token])
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    # Returns the first enabled Telegram connector, if any.
    def self.enabled_connector
      Connector.by_type("telegram").enabled.first
    end

    # ── Bot API ────────────────────────────────────────────────────────────

    # Build a Telegram::Bot::Api client from stored credentials.
    def bot_api
      @bot_api ||= ::Telegram::Bot::Api.new(bot_token)
    end

    # Fetch bot info from Telegram API and cache username.
    # NOTE: Caller must save the Connector record after calling this.
    def fetch_bot_info!
      user = bot_api.get_me
      self.bot_username = user.username
      user
    rescue StandardError => e
      raise e unless vcr_unhandled_request_error?(e)

      nil
    end

    # Register a webhook with Telegram.
    # NOTE: Caller must save the Connector record after calling this.
    def register_webhook!(url, secret: nil)
      self.webhook_url = url
      self.webhook_secret = secret || SecureRandom.hex(32)

      bot_api.set_webhook(
        url: webhook_url,
        secret_token: webhook_secret,
        allowed_updates: ["message", "callback_query"],
      )
    rescue StandardError => e
      raise e unless vcr_unhandled_request_error?(e)

      nil
    end

    # Remove the webhook from Telegram.
    # NOTE: Caller must save the Connector record after calling this.
    def remove_webhook!
      bot_api.delete_webhook
      self.webhook_url = nil
      self.webhook_secret = nil
    rescue StandardError => e
      raise e unless vcr_unhandled_request_error?(e)

      nil
    end

    # Send a text message to a Telegram chat.
    def send_message(chat_id, text, parse_mode: "Markdown")
      bot_api.send_message(
        chat_id:,
        text:,
        parse_mode:,
      )
    rescue ::Telegram::Bot::Exceptions::ResponseError => e
      # Fallback to plain text if Markdown parsing fails
      raise e unless parse_mode == "Markdown"

      bot_api.send_message(chat_id:, text:)
    rescue StandardError => e
      raise e unless vcr_unhandled_request_error?(e)

      nil
    end

    # Stream a partial text response while the final message is being generated.
    # Always sends plain text (no parse_mode) since partial streaming text
    # often contains incomplete Markdown that Telegram would reject.
    # Errors are silently logged — draft failures must never abort streaming.
    def send_message_draft(chat_id, draft_id, text)
      bot_api.call("sendMessageDraft", chat_id:, draft_id:, text:)
    rescue StandardError => e
      Rails.logger.warn("[Telegram] sendMessageDraft failed: #{e.message}") unless vcr_unhandled_request_error?(e)
      nil
    end

    # Edit an existing text message in a Telegram chat.
    def edit_message(chat_id, message_id, text, parse_mode: "Markdown")
      bot_api.edit_message_text(
        chat_id:,
        message_id:,
        text:,
        parse_mode:,
      )
    rescue ::Telegram::Bot::Exceptions::ResponseError => e
      return nil if message_not_modified_error?(e)

      raise e unless parse_mode == "Markdown"

      bot_api.edit_message_text(chat_id:, message_id:, text:)
    rescue StandardError => e
      raise e unless vcr_unhandled_request_error?(e)

      nil
    end

    # Send a file document to a Telegram chat.
    # Accepts an ActiveStorage::Blob and sends it via the Telegram Bot API.
    def send_document(chat_id, blob, caption: nil)
      blob.open do |tempfile|
        document = Faraday::Multipart::FilePart.new(
          tempfile.path,
          blob.content_type || "application/octet-stream",
          blob.filename.to_s,
        )
        params = { chat_id:, document: }
        params[:caption] = caption if caption.present?
        bot_api.send_document(**params)
      end
    rescue ::Telegram::Bot::Exceptions::ResponseError => e
      Rails.logger.error("[Telegram] sendDocument failed: #{e.message}")
      nil
    rescue StandardError => e
      raise e unless vcr_unhandled_request_error?(e)

      nil
    end

    # Send a "typing" action indicator.
    def send_typing(chat_id)
      bot_api.send_chat_action(chat_id:, action: "typing")
    rescue ::Telegram::Bot::Exceptions::ResponseError
      # Non-critical, ignore errors
    rescue StandardError => e
      raise e unless vcr_unhandled_request_error?(e)

      # Non-critical, ignore errors
    end

    # ── Configuration ──────────────────────────────────────────────────────

    def to_configuration
      config = super
      config["bot_token"] = nil if config["bot_token"].blank?
      config["webhook_secret"] = nil if config["webhook_secret"].blank?
      config
    end

    def summary
      bot_username.present? ? "@#{bot_username}" : "Telegram configured"
    end

    def show_extra_partial_name
      "telegram_setup_card"
    end

    private

    def vcr_unhandled_request_error?(error)
      defined?(VCR::Errors::UnhandledHTTPRequestError) && error.is_a?(VCR::Errors::UnhandledHTTPRequestError)
    end

    def webhook_secret_uniqueness
      return if webhook_secret.blank?

      scope = Connector.by_type("telegram").where("configuration ->> 'webhook_secret' = ?", webhook_secret)
      scope = scope.where.not(id: _connector_record.id) if _connector_record&.persisted?
      errors.add(:webhook_secret, :taken) if scope.exists?
    end

    def message_not_modified_error?(error)
      error.message.to_s.include?("message is not modified")
    end
  end
end
