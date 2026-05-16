# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telegram::ChatResponseJob do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let!(:model) { create(:model, model_id: "gpt-4.1", provider: "openai") }
  let(:connector) { create(:connector, :telegram, :enabled, tenant:) }
  let(:agent) { create(:agent, operation: tenant.default_operation, model_id: model.model_id) }
  let(:user) { create(:user, tenant:) }
  let(:channel) { create(:channel, :telegram, tenant:, connector:) }
  let!(:target) { create(:channel_target, channel:, target: agent, default: true) }
  let(:conversation) do
    create(
      :channel_conversation,
      channel:,
      channel_target: target,
      external_conversation_id: "789",
      external_thread_id: "",
    )
  end
  let(:chat) do
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
  let(:job) { described_class.new }

  before do
    conversation.update!(chat:)
    allow(job).to receive(:find_chat).and_return(chat)
    allow(chat).to receive(:configure_for_agent)
    allow(connector).to receive_messages(
      send_message: { "message_id" => 12_345 },
      send_message_draft: true,
      send_typing: true,
      send_document: true,
    )
    allow(Capabilities::EventDispatcher).to receive(:dispatch).and_return(false)
    allow(chat).to receive(:ask) { |_content, **_ask_options, &block| block.call(double(content: "Hello!")) }
  end

  it "sends a response back to the Telegram chat" do
    job.perform(chat_id: chat.id, channel_id: channel.id, tenant_id: tenant.id, content: "Hello")

    expect(connector).to have_received(:send_typing).with("789")
    expect(connector).to have_received(:send_message_draft).at_least(:once)
    expect(connector).to have_received(:send_message).with("789", "Hello!")
    expect(chat.reload).to be_idle
  end

  it "normalizes legacy telegram titles so inspector rows become identifiable" do
    chat.update!(title: "Telegram Chat")
    create(:message, :user, chat:, content: "Show me my latest Telegram conversation")

    job.perform(chat_id: chat.id, channel_id: channel.id, tenant_id: tenant.id, content: "Hello")

    expect(chat.reload.title).to eq("Show me my latest Telegram conversation")
  end

  it "splits long responses into multiple Telegram messages" do
    allow(chat).to receive(:ask) do |_content, **_ask_options, &block|
      block.call(double(content: "x" * 5000))
    end

    job.perform(chat_id: chat.id, channel_id: channel.id, tenant_id: tenant.id, content: "Hello")

    expect(connector).to have_received(:send_message).at_least(:twice)
  end

  it "does not stream drafts when the channel disables streaming" do
    channel.update!(configuration: channel.configuration.merge("streaming_enabled" => false))

    job.perform(chat_id: chat.id, channel_id: channel.id, tenant_id: tenant.id, content: "Hello")

    expect(connector).not_to have_received(:send_message_draft)
    expect(connector).to have_received(:send_message).with("789", "Hello!")
  end

  it "passes downloaded photos into the LLM request" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("image-data"),
      filename: "photo.jpg",
      content_type: "image/jpeg",
    )
    allow(job).to receive(:download_photo).with("photo_123").and_return([blob])

    job.perform(
      chat_id: chat.id,
      channel_id: channel.id,
      tenant_id: tenant.id,
      content: "Hello",
      photo_file_id: "photo_123",
    )

    expect(chat).to have_received(:ask).with("Hello", with: [blob])
  end

  it "sends tool-generated file attachments as Telegram documents" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("report-data"),
      filename: "report.txt",
      content_type: "text/plain",
    )
    allow(chat).to receive(:ask) do |_content, **_ask_options, &block|
      create(:message, :tool, chat:, content: "https://example.test/dl/#{blob.signed_id}/report.txt")
      block.call(double(content: "Hello!"))
    end

    job.perform(chat_id: chat.id, channel_id: channel.id, tenant_id: tenant.id, content: "Hello")

    expect(connector).to have_received(:send_document).with("789", blob, caption: "📎 report.txt")
  end

  it "does not resend historical file attachments on later Telegram replies" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("report-data"),
      filename: "report.txt",
      content_type: "text/plain",
    )
    create(:message, :tool, chat:, content: "https://example.test/dl/#{blob.signed_id}/report.txt")

    job.perform(chat_id: chat.id, channel_id: channel.id, tenant_id: tenant.id, content: "Hello")

    expect(connector).not_to have_received(:send_document)
  end

  it "handles errors gracefully" do
    allow(Rails.logger).to receive(:error)
    allow(chat).to receive(:ask).and_raise(StandardError, "LLM error")

    job.perform(chat_id: chat.id, channel_id: channel.id, tenant_id: tenant.id, content: "Hello")

    expect(Rails.logger).to have_received(:error).with(/LLM error/)
    expect(connector).to have_received(:send_message)
      .with("789", "Sorry, I encountered an error processing your message.")
  end

  it "does not send empty responses" do
    allow(chat).to receive(:ask) { |_content, **_ask_options, &block| block.call(double(content: nil)) }

    job.perform(chat_id: chat.id, channel_id: channel.id, tenant_id: tenant.id, content: "Hello")

    expect(connector).not_to have_received(:send_message)
  end

  it "returns early when the chat has no agent" do
    chat_without_agent = create(
      :chat,
      :channel_context,
      agent: nil,
      user:,
      model:,
      channel:,
      channel_target: target,
      channel_conversation: conversation,
      title: Chat::DEFAULT_TITLE,
    )
    allow(job).to receive(:find_chat).and_return(chat_without_agent)

    job.perform(chat_id: chat_without_agent.id, channel_id: channel.id, tenant_id: tenant.id, content: "Hello")

    expect(connector).not_to have_received(:send_typing)
  end

  it "returns early when the chat is missing Telegram delivery context" do
    chat_without_delivery_context = create(
      :chat,
      agent:,
      user:,
      model:,
      channel: nil,
      channel_target: nil,
      channel_conversation: nil,
      execution_context: :channel,
      title: Chat::DEFAULT_TITLE,
    )
    allow(job).to receive(:find_chat).and_return(chat_without_delivery_context)

    job.perform(chat_id: chat.id, channel_id: channel.id, tenant_id: tenant.id, content: "Hello")

    expect(connector).not_to have_received(:send_typing)
  end

  it "discards missing chats without raising" do
    expect do
      described_class.perform_now(chat_id: 99_999_999, channel_id: channel.id, content: "Hello", tenant_id: tenant.id)
    end.not_to raise_error
  end

  it "finds chats without tenant scoping when no tenant id is provided" do
    expect(described_class.new.send(:find_chat, chat.id, channel_id: channel.id, tenant_id: nil)).to eq(chat)
  end

  it "logs file attachment delivery failures without raising" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("report-data"),
      filename: "report.txt",
      content_type: "text/plain",
    )
    allow(Rails.logger).to receive(:error)
    job.instance_variable_set(:@connector, connector)
    job.instance_variable_set(:@telegram_chat_id, "789")
    allow(job).to receive(:extract_file_blobs).and_return([blob])
    allow(connector).to receive(:send_document).and_raise(StandardError, "upload failed")

    expect { job.send(:send_file_attachments) }.not_to raise_error
    expect(Rails.logger).to have_received(:error).with(/File attachment error: upload failed/)
  end

  it "returns an empty attachment list when photo download fails" do
    allow(Rails.logger).to receive(:error)
    allow(job).to receive(:fetch_and_store_photo).with("photo_123").and_raise(StandardError, "download failed")

    expect(job.send(:download_photo, "photo_123")).to eq([])
    expect(Rails.logger).to have_received(:error).with(/Photo download error: download failed/)
  end

  it "skips draft updates when the stream interval has not elapsed yet" do
    job.instance_variable_set(:@connector, connector)
    job.instance_variable_set(:@telegram_chat_id, "789")
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(1.0)

    job.send(:maybe_send_draft, "draft", 123, 0.75, true) { raise "should not yield" }

    expect(connector).not_to have_received(:send_message_draft)
  end

  it "returns no signed ids for blank tool output" do
    expect(job.send(:extract_signed_ids, "")).to eq([])
  end

  it "ignores invalid signed blob ids" do
    allow(ActiveStorage::Blob).to receive(:find_signed)
      .with("bad-signature")
      .and_raise(ActiveSupport::MessageVerifier::InvalidSignature)

    expect(job.send(:find_signed_blob, "bad-signature")).to be_nil
  end

  it "downloads a photo when Telegram returns an object-style file path" do
    file_info = Struct.new(:file_path).new("photos/file_123.jpg")
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive_messages(body: "binary-image", content_type: nil)
    bot_api = double("Telegram bot api", get_file: file_info) # rubocop:disable RSpec/VerifiedDoubles

    job.instance_variable_set(:@connector, connector)
    allow(connector).to receive_messages(bot_api:, bot_token: "bot-token")
    allow(Net::HTTP).to receive(:get_response).and_return(response)

    blobs = job.send(:fetch_and_store_photo, "photo_123")

    expect(blobs.size).to eq(1)
    expect(blobs.first.filename.to_s).to eq("file_123.jpg")
    expect(blobs.first.content_type).to eq("image/jpeg")
  end

  it "logs failed photo downloads when Telegram returns a non-success response" do
    allow(Rails.logger).to receive(:error)
    bot_api = double("Telegram bot api", get_file: { "result" => { "file_path" => "photos/file_123.jpg" } }) # rubocop:disable RSpec/VerifiedDoubles
    response = Net::HTTPNotFound.new("1.1", "404", "Not Found")

    job.instance_variable_set(:@connector, connector)
    allow(connector).to receive_messages(bot_api:, bot_token: "bot-token")
    allow(Net::HTTP).to receive(:get_response).and_return(response)

    expect(job.send(:fetch_and_store_photo, "photo_123")).to eq([])
    expect(Rails.logger).to have_received(:error).with(/Failed to download photo: 404/)
  end
end
