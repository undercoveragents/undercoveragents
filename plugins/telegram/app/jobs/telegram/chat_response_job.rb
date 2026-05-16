# frozen_string_literal: true

module Telegram
  class ChatResponseJob < BaseChatResponseJob
    LEGACY_DEFAULT_TITLE = "Telegram Chat"
    TELEGRAM_MESSAGE_LIMIT = 4096
    STREAM_INTERVAL = 0.5
    DOWNLOAD_URL_PATTERN = %r{/dl/([A-Za-z0-9_\-=]+)/}

    queue_as :default

    discard_on ActiveRecord::RecordNotFound

    def perform(chat_id:, channel_id:, content:, photo_file_id: nil, tenant_id: nil)
      load_chat_context(chat_id, channel_id:, tenant_id:)
      return unless deliverable_chat?

      respond_to_message(content, photo_file_id:)
    rescue StandardError => e
      Rails.logger.error "[Telegram::ChatResponseJob] Error: #{e.message}"
      @connector&.send_message(@telegram_chat_id, "Sorry, I encountered an error processing your message.")
    ensure
      finalize_response_chat
    end

    private

    def load_chat_context(chat_id, channel_id:, tenant_id: nil)
      @chat = find_chat(chat_id, channel_id:, tenant_id:)
      @channel = @chat.channel
      @agent = @chat.agent
      @connector = @channel&.connector
      @telegram_chat_id = @chat.channel_conversation&.external_conversation_id
    end

    def deliverable_chat?
      @agent.present? && @connector.present? && @telegram_chat_id.present?
    end

    def find_chat(chat_id, channel_id:, tenant_id: nil)
      scope = Chat.where(id: chat_id, channel_id:)
      scope = scope.joins(:channel).where(channels: { tenant_id: }) if tenant_id.present?
      scope.includes(:channel, :channel_conversation).first!
    end

    def respond_to_message(content, photo_file_id: nil)
      configure_chat
      @connector.send_typing(@telegram_chat_id)
      initial_message_id = @chat.messages.maximum(:id).to_i

      response_text = build_response(content, ask_options(photo_file_id), streaming: @channel.streaming_enabled)
      send_response(response_text)
      send_file_attachments(since_message_id: initial_message_id)
    end

    def ask_options(photo_file_id)
      attachments = download_photo(photo_file_id)
      attachments.any? ? { with: attachments } : {}
    end

    def build_response(content, ask_options, streaming:)
      response_text = +""
      draft_id = SecureRandom.random_number(2_147_483_647) + 1
      last_draft_at = 0.0

      @chat.ask(content, **ask_options) do |chunk|
        next if chunk.content.nil?

        response_text << chunk.content
        next if response_text.length > TELEGRAM_MESSAGE_LIMIT

        maybe_send_draft(response_text, draft_id, last_draft_at, streaming) do |ts|
          last_draft_at = ts
        end
      end

      response_text
    end

    def maybe_send_draft(text, draft_id, last_draft_at, streaming)
      return unless streaming

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return unless now - last_draft_at >= STREAM_INTERVAL

      @connector.send_message_draft(@telegram_chat_id, draft_id, text)
      yield now
    end

    def configure_chat
      @chat.configure_for_agent(@agent)
    end

    def send_response(text)
      return if text.blank?

      if text.length <= TELEGRAM_MESSAGE_LIMIT
        @connector.send_message(@telegram_chat_id, text)
      else
        text.scan(/.{1,#{TELEGRAM_MESSAGE_LIMIT}}/mo).each do |chunk|
          @connector.send_message(@telegram_chat_id, chunk)
        end
      end
    end

    # Detect file blobs referenced in tool-result messages and send them
    # as downloadable Telegram documents.
    def send_file_attachments(since_message_id: 0)
      blobs = extract_file_blobs(since_message_id:)
      blobs.each do |blob|
        @connector.send_document(@telegram_chat_id, blob, caption: "📎 #{blob.filename}")
      end
    rescue StandardError => e
      Rails.logger.error "[Telegram::ChatResponseJob] File attachment error: #{e.message}"
    end

    # Scan recent tool-role messages for download URLs produced by
    # MissionToolAdapter (pattern: /dl/{signed_id}/{filename}).
    def extract_file_blobs(since_message_id: 0)
      tool_messages = @chat.messages.where(role: "tool").where("id > ?", since_message_id).order(id: :desc).limit(20)
      signed_ids = tool_messages.filter_map { |msg| extract_signed_ids(msg.content) }.flatten.uniq
      signed_ids.filter_map { |signed_id| find_signed_blob(signed_id) }
    end

    def find_signed_blob(signed_id)
      ActiveStorage::Blob.find_signed(signed_id)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      nil
    end

    def extract_signed_ids(content)
      return [] if content.blank?

      content.scan(DOWNLOAD_URL_PATTERN).flatten
    end

    def download_photo(file_id)
      return [] if file_id.blank?

      fetch_and_store_photo(file_id)
    rescue StandardError => e
      Rails.logger.error "[Telegram::ChatResponseJob] Photo download error: #{e.message}"
      []
    end

    def fetch_and_store_photo(file_id)
      file_info = @connector.bot_api.get_file(file_id:)
      file_path =
        if file_info.respond_to?(:file_path)
          file_info.file_path
        else
          (file_info["result"] || file_info)["file_path"]
        end
      url = "https://api.telegram.org/file/bot#{@connector.bot_token}/#{file_path}"
      response = Net::HTTP.get_response(URI(url))

      return log_photo_failure(response.code) unless response.is_a?(Net::HTTPSuccess)

      [create_photo_blob(response, file_path)]
    end

    def create_photo_blob(response, file_path)
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(response.body),
        filename: File.basename(file_path),
        content_type: response.content_type || "image/jpeg",
      )
    end

    def log_photo_failure(code)
      Rails.logger.error "[Telegram::ChatResponseJob] Failed to download photo: #{code}"
      []
    end

    def finalize_response_chat
      return unless @chat

      normalize_legacy_default_title!
      finalize_chat(@chat)
    end

    def normalize_legacy_default_title!
      return unless @chat.title == LEGACY_DEFAULT_TITLE

      @chat.title = Chat::DEFAULT_TITLE
    end
  end
end
