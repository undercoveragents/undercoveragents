# frozen_string_literal: true

module Telegram
  class MessageProcessor
    COMMANDS = ["start", "help", "newchat", "link"].freeze

    def initialize(channel:, **message_payload)
      @channel = channel
      @telegram_chat_id = message_payload[:telegram_chat_id]
      @telegram_user_id = message_payload[:telegram_user_id]
      @telegram_username = message_payload[:telegram_username]
      @text = message_payload[:text]&.strip
      @photo = message_payload[:photo]
    end

    def process
      return handle_command if command?
      return handle_photo if @photo.present?
      return send_reply("Please send a text message or image.") if @text.blank?

      handle_message
    end

    private

    # ── Command routing ────────────────────────────────────────────────────

    def command?
      @text&.start_with?("/")
    end

    def handle_command
      cmd, *args = @text.split
      cmd = cmd.downcase.delete_prefix("/").split("@").first # Handle /cmd@botname

      case cmd
      when "start" then handle_start
      when "help" then handle_help
      when "link" then handle_link(args.first)
      when "newchat" then handle_new_chat
      else
        send_reply("Unknown command: /#{cmd}\nUse /help to see available commands.")
      end
    end

    # ── /start ─────────────────────────────────────────────────────────────

    def handle_start
      return send_unlinked_message unless find_user

      send_reply(@channel.welcome_message.presence || Channels::Telegram::DEFAULT_WELCOME_MESSAGE)
    end

    # ── /help ──────────────────────────────────────────────────────────────

    def handle_help
      help_text = <<~HELP
        *Available Commands*

        /start — Start the bot and see a welcome message
        /newchat — Start a new conversation (clears chat context)
        /help — Show this help message
        /link <token> — Link your account (get the token from your profile page)

        *How to use:*
        Simply send a text message and I'll respond. You can also send images for analysis.
        Each conversation maintains context, so I'll remember what we've discussed. Use /newchat to start fresh.
      HELP
      send_reply(help_text)
    end

    # ── /link ──────────────────────────────────────────────────────────────

    def handle_link(token)
      if token.blank?
        send_reply(
          "Please provide your link token.\n" \
          "Usage: /link YOUR_TOKEN\n\n" \
          "Get your token from your profile page in the web application.",
        )
        return
      end

      link_request = Channels::TelegramLinkRequest.find_by_token(channel: @channel, token:)
      return send_invalid_link_message unless link_request

      identity = @channel.channel_identities.find_or_initialize_by(user: link_request.user)
      identity.external_user_id = @telegram_user_id.to_s
      identity.external_username = @telegram_username
      identity.linked_at = Time.current
      identity.metadata = identity.metadata.merge("telegram_chat_id" => @telegram_chat_id.to_s)
      identity.save!
      Channels::TelegramLinkRequest.clear_for(channel: @channel, user: link_request.user)

      send_reply("Account linked successfully! Welcome, #{link_request.user.display_name}. You can now start chatting.")
    rescue ActiveRecord::RecordInvalid
      send_invalid_link_message
    end

    # ── /newchat ───────────────────────────────────────────────────────────

    def handle_new_chat
      user = find_user
      return send_unlinked_message unless user

      agent = find_agent
      return send_no_agent_message unless agent

      create_chat(user, agent, conversation: find_or_create_conversation(user))
      send_reply("New conversation started! Go ahead and send your message.")
    end

    # ── Regular message ────────────────────────────────────────────────────

    def handle_message
      user = find_user
      return send_unlinked_message unless user

      agent = find_agent
      return send_no_agent_message unless agent

      chat = find_or_create_chat(user, agent)

      Telegram::ChatResponseJob.perform_later(
        chat_id: chat.id,
        channel_id: @channel.id,
        tenant_id: @channel.tenant_id,
        content: @text,
        photo_file_id: nil,
      )
    end

    # ── Photo handling ─────────────────────────────────────────────────────

    def handle_photo
      user = find_user
      return send_unlinked_message unless user

      agent = find_agent
      return send_no_agent_message unless agent

      chat = find_or_create_chat(user, agent)
      caption = @photo[:caption].presence || "Please analyze this image."

      Telegram::ChatResponseJob.perform_later(
        chat_id: chat.id,
        channel_id: @channel.id,
        tenant_id: @channel.tenant_id,
        content: caption,
        photo_file_id: @photo[:file_id],
      )
    end

    # ── Helpers ────────────────────────────────────────────────────────────

    def find_user
      linked_identity&.user
    end

    def find_agent
      target = @channel.default_target
      return unless target&.target_type == "Agent"

      target.target
    end

    def find_or_create_chat(user, agent)
      conversation = find_or_create_conversation(user)
      existing_chat = conversation.chat

      return existing_chat if existing_chat&.agent_id == agent.id

      create_chat(user, agent, conversation:)
    end

    def create_chat(user, agent, conversation:)
      model = Model.find_by(model_id: agent.resolved_model_id)
      chat = Chat.create!(
        agent:,
        user:,
        model:,
        channel: @channel,
        channel_target: @channel.default_target,
        execution_context: :channel,
        title: Chat::DEFAULT_TITLE,
      )
      conversation.update!(chat:, channel_target: @channel.default_target, channel_identity: linked_identity)
      chat.update!(channel_conversation: conversation)
      chat
    end

    def find_or_create_conversation(user)
      conversation = @channel.channel_conversations.find_or_initialize_by(
        external_conversation_id: @telegram_chat_id.to_s,
        external_thread_id: "",
      )
      return conversation.tap(&:save!) if conversation.persisted?

      conversation.channel_identity = linked_identity
      conversation.channel_target = @channel.default_target
      conversation.metadata = conversation.metadata.merge("user_id" => user.id)
      conversation.save!
      conversation
    end

    def linked_identity
      return @linked_identity if defined?(@linked_identity)

      @linked_identity = @channel.channel_identities.find_by(external_user_id: @telegram_user_id.to_s)
    end

    def send_reply(text)
      @channel.connector.send_message(@telegram_chat_id, text)
    end

    def send_unlinked_message
      send_reply(
        "Your Telegram account is not linked yet.\n\n" \
        "To get started:\n" \
        "1. Log in to the web application\n" \
        "2. Go to your Profile page\n" \
        "3. Generate a Telegram link token for #{@channel.name}\n" \
        "4. Send the /link command with your token here",
      )
    end

    def send_no_agent_message
      send_reply("No AI agent is configured for Telegram at this time. Please contact an administrator.")
    end

    def send_invalid_link_message
      send_reply(
        "Invalid or expired link token. Please generate a new token from your profile page and try again.",
      )
    end
  end
end
