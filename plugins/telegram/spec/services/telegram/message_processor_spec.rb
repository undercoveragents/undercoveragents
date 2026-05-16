# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telegram::MessageProcessor do
  let(:tenant) { create(:tenant) }
  let(:operation) { create(:operation, tenant:) }
  let!(:model) { create(:model, model_id: "gpt-4.1", provider: "openai") }
  let(:agent) { create(:agent, operation:, model_id: model.model_id, enabled: true, selectable: true) }
  let(:connector) { create(:connector, :telegram, :enabled, tenant:, bot_username: "test_bot") }
  let(:channel) { create(:channel, :telegram, tenant:, connector:) }
  let!(:target) { create(:channel_target, channel:, target: agent, default: true) }
  let(:telegram_chat_id) { 123_456 }
  let(:telegram_user_id) { 789_012 }
  let(:telegram_username) { "testuser" }

  before do
    allow(connector).to receive(:send_message)
    allow(Telegram::ChatResponseJob).to receive(:perform_later)
  end

  def create_linked_identity(user)
    create(
      :channel_identity,
      channel:,
      user:,
      external_user_id: telegram_user_id.to_s,
      linked_at: Time.current,
    )
  end

  def create_existing_channel_chat(user)
    conversation = create_existing_conversation(user)
    existing_chat = build_existing_chat(user, conversation)
    conversation.update!(chat: existing_chat)
    existing_chat
  end

  def create_existing_conversation(user)
    identity = create_linked_identity(user)

    create(
      :channel_conversation,
      channel:,
      channel_target: target,
      channel_identity: identity,
      external_conversation_id: telegram_chat_id.to_s,
      external_thread_id: "",
    )
  end

  def build_existing_chat(user, conversation)
    create(
      :chat,
      :channel_context,
      agent:,
      user:,
      model:,
      channel:,
      channel_target: target,
      channel_conversation: conversation,
      title: Chat::DEFAULT_TITLE,
    )
  end

  it "sends an unlinked message for /start when the user is not linked" do
    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "/start").process

    expect(connector).to have_received(:send_message).with(telegram_chat_id, a_string_including("not linked"))
  end

  it "sends the configured welcome message for /start when the user is linked" do
    user = create(:user, tenant:)
    create_linked_identity(user)

    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "/start").process

    expect(connector).to have_received(:send_message).with(telegram_chat_id, channel.welcome_message)
  end

  it "falls back to the default welcome message when the channel welcome copy is blank" do
    user = create(:user, tenant:)
    create_linked_identity(user)
    allow(channel).to receive(:welcome_message).and_return("")

    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "/start").process

    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, Channels::Telegram::DEFAULT_WELCOME_MESSAGE)
  end

  it "sends help text for /help" do
    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "/help").process

    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, a_string_including("Available Commands"))
  end

  it "handles /help addressed to the bot username" do
    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "/help@test_bot").process

    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, a_string_including("Available Commands"))
  end

  it "links a user with a valid token" do
    user = create(:user, tenant:)
    token = Channels::TelegramLinkRequest.issue!(channel:, user:)

    described_class.new(
      channel:,
      telegram_chat_id:,
      telegram_user_id:,
      telegram_username:,
      text: "/link #{token}",
    ).process

    identity = channel.channel_identities.find_by(user:)
    expect(identity.external_user_id).to eq(telegram_user_id.to_s)
    expect(identity.external_username).to eq(telegram_username)
    expect(Channels::TelegramLinkRequest.find_by(channel:, user:)).to be_nil
    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, a_string_including("linked successfully"))
  end

  it "rejects an invalid link token" do
    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "/link invalid-token").process

    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, a_string_including("Invalid or expired"))
  end

  it "shows usage info when /link has no token" do
    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "/link").process

    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, a_string_including("provide your link token"))
  end

  it "reports an invalid link token when the identity cannot be saved" do
    user = create(:user, tenant:)
    token = Channels::TelegramLinkRequest.issue!(channel:, user:)
    invalid_identity = instance_double(ChannelIdentity, metadata: {})

    allow(channel.channel_identities).to receive(:find_or_initialize_by).with(user:).and_return(invalid_identity)
    allow(invalid_identity).to receive(:external_user_id=)
    allow(invalid_identity).to receive(:external_username=)
    allow(invalid_identity).to receive(:linked_at=)
    allow(invalid_identity).to receive(:metadata=)
    allow(invalid_identity).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(ChannelIdentity.new))

    described_class.new(
      channel:,
      telegram_chat_id:,
      telegram_user_id:,
      telegram_username:,
      text: "/link #{token}",
    ).process

    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, a_string_including("Invalid or expired link token"))
  end

  it "creates a new channel-scoped chat for /newchat" do
    user = create(:user, tenant:)
    create_linked_identity(user)

    expect do
      described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "/newchat").process
    end.to change(Chat, :count).by(1)

    chat = Chat.order(:id).last
    expect(chat).to have_attributes(
      execution_context: "channel",
      channel:,
      channel_target: target,
      title: Chat::DEFAULT_TITLE,
    )
    expect(chat.channel_conversation).to have_attributes(external_conversation_id: telegram_chat_id.to_s)
    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, a_string_including("New conversation started"))
  end

  it "sends an unlinked message for /newchat when the user is not linked" do
    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "/newchat").process

    expect(connector).to have_received(:send_message).with(telegram_chat_id, a_string_including("not linked"))
  end

  it "treats non-agent targets as unavailable for /newchat" do
    user = create(:user, tenant:)
    mission_target = instance_double(ChannelTarget, target_type: "Mission")
    create_linked_identity(user)
    allow(channel).to receive(:default_target).and_return(mission_target)

    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "/newchat").process

    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, a_string_including("No AI agent"))
  end

  it "sends no-agent copy when the channel has no default target" do
    user = create(:user, tenant:)
    create_linked_identity(user)
    allow(channel).to receive(:default_target).and_return(nil)

    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "Hello bot").process

    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, a_string_including("No AI agent"))
  end

  it "treats agent-shaped targets without a backing agent as unavailable" do
    user = create(:user, tenant:)
    empty_agent_target = instance_double(ChannelTarget, target_type: "Agent", target: nil)
    create_linked_identity(user)
    allow(channel).to receive(:default_target).and_return(empty_agent_target)

    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "Hello bot").process

    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, a_string_including("No AI agent"))
  end

  it "asks for text when the message body is blank" do
    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "").process

    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, a_string_including("text message or image"))
  end

  it "reports an unknown command" do
    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "/unknown").process

    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, a_string_including("Unknown command"))
  end

  it "enqueues a chat response job for a linked text message" do
    user = create(:user, tenant:)
    create_linked_identity(user)

    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "Hello bot").process

    chat = Chat.order(:id).last
    expect(Telegram::ChatResponseJob).to have_received(:perform_later).with(
      hash_including(
        chat_id: chat.id,
        channel_id: channel.id,
        tenant_id: tenant.id,
        content: "Hello bot",
        photo_file_id: nil,
      ),
    )
  end

  it "sends an unlinked message for a regular text message when the user is not linked" do
    described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "Hello bot").process

    expect(connector).to have_received(:send_message).with(telegram_chat_id, a_string_including("not linked"))
  end

  it "reuses the existing conversation chat for subsequent text messages" do
    user = create(:user, tenant:)
    existing_chat = create_existing_channel_chat(user)

    expect do
      described_class.new(channel:, telegram_chat_id:, telegram_user_id:, text: "Hello again").process
    end.not_to change(Chat, :count)

    expect(Telegram::ChatResponseJob).to have_received(:perform_later)
      .with(hash_including(chat_id: existing_chat.id, content: "Hello again"))
  end

  it "enqueues a chat response job with the uploaded photo" do
    user = create(:user, tenant:)
    create_linked_identity(user)

    described_class.new(
      channel:,
      telegram_chat_id:,
      telegram_user_id:,
      photo: { file_id: "photo_123", caption: "check this" },
    ).process

    expect(Telegram::ChatResponseJob).to have_received(:perform_later)
      .with(hash_including(content: "check this", photo_file_id: "photo_123"))
  end

  it "sends an unlinked message for an uploaded photo when the user is not linked" do
    described_class.new(
      channel:,
      telegram_chat_id:,
      telegram_user_id:,
      photo: { file_id: "photo_123", caption: "check this" },
    ).process

    expect(connector).to have_received(:send_message).with(telegram_chat_id, a_string_including("not linked"))
  end

  it "uses a default caption for a photo-only message" do
    user = create(:user, tenant:)
    create_linked_identity(user)

    described_class.new(
      channel:,
      telegram_chat_id:,
      telegram_user_id:,
      photo: { file_id: "photo_123", caption: nil },
    ).process

    expect(Telegram::ChatResponseJob).to have_received(:perform_later)
      .with(hash_including(content: "Please analyze this image.", photo_file_id: "photo_123"))
  end

  it "treats non-agent targets as unavailable for photos" do
    user = create(:user, tenant:)
    mission_target = instance_double(ChannelTarget, target_type: "Mission")
    create_linked_identity(user)
    allow(channel).to receive(:default_target).and_return(mission_target)

    described_class.new(
      channel:,
      telegram_chat_id:,
      telegram_user_id:,
      photo: { file_id: "photo_123", caption: "check this" },
    ).process

    expect(connector).to have_received(:send_message)
      .with(telegram_chat_id, a_string_including("No AI agent"))
  end
end
