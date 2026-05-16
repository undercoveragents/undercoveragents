# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Telegram webhook" do
  let(:tenant) { create(:tenant) }
  let(:connector) { create(:connectors_telegram, :with_webhook, tenant:, enabled: true) }
  let(:channel) { create(:channel, :telegram, tenant:, connector:, enabled: true) }
  let(:json_headers) { { "CONTENT_TYPE" => "application/json" } }

  def webhook_path(token)
    "/channels/telegram/#{channel.to_param}/webhook/#{token}"
  end

  def payload(text: "/help", photo: nil, caption: nil)
    message = {
      message_id: 1,
      chat: { id: 12_345, type: "private" },
      from: { id: 67_890, is_bot: false, first_name: "Test", username: "testuser" },
      date: Time.current.to_i,
    }
    message[:text] = text if text
    if photo
      message[:photo] = photo
      message[:caption] = caption if caption
    end

    { update_id: 1, message: }
  end

  it "returns ok for a valid webhook secret" do
    post webhook_path(connector.webhook_secret), params: payload.to_json, headers: json_headers

    expect(response).to have_http_status(:ok)
  end

  it "enqueues a Telegram process job" do
    expect do
      post webhook_path(connector.webhook_secret), params: payload.to_json, headers: json_headers
    end.to have_enqueued_job(Telegram::ProcessMessageJob)
      .with(
        hash_including(
          channel_id: channel.id,
          tenant_id: tenant.id,
          telegram_chat_id: 12_345,
          telegram_user_id: 67_890,
        ),
      )
  end

  it "returns unauthorized for an invalid token" do
    post webhook_path("invalid-token"), params: payload.to_json, headers: json_headers

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns unauthorized when the Telegram channel has no connector" do
    connectorless_channel = build(:channel, :telegram, tenant:, connector: nil, enabled: true)
    connectorless_channel.save!(validate: false)

    post "/channels/telegram/#{connectorless_channel.to_param}/webhook/#{connector.webhook_secret}",
         params: payload.to_json,
         headers: json_headers

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns bad_request for invalid JSON" do
    post webhook_path(connector.webhook_secret), params: "not-json", headers: json_headers

    expect(response).to have_http_status(:bad_request)
  end

  it "returns ok when the update has no message" do
    post webhook_path(connector.webhook_secret), params: { update_id: 1 }.to_json, headers: json_headers

    expect(response).to have_http_status(:ok)
  end

  it "extracts the largest photo and caption" do
    photo = [
      { file_id: "small_123", file_unique_id: "a", width: 90, height: 90, file_size: 1000 },
      { file_id: "large_456", file_unique_id: "b", width: 800, height: 600, file_size: 5000 },
    ]

    expect do
      post webhook_path(connector.webhook_secret),
           params: payload(text: nil, photo:, caption: "Check this out").to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
    end.to have_enqueued_job(Telegram::ProcessMessageJob)
      .with(hash_including(photo: hash_including(file_id: "large_456", caption: "Check this out")))
  end

  it "extracts a photo even when the Telegram message object has no caption method" do
    photo_message = Class.new do
      def photo
        [Struct.new(:file_id).new("large_456")]
      end

      def chat
        Struct.new(:id).new(12_345)
      end

      def from
        Struct.new(:id, :username).new(67_890, "testuser")
      end

      def text
        nil
      end
    end.new
    update = instance_double(Telegram::Bot::Types::Update, message: photo_message)
    allow(Telegram::Bot::Types::Update).to receive(:new).and_return(update)

    expect do
      post webhook_path(connector.webhook_secret), params: payload.to_json, headers: json_headers
    end.to have_enqueued_job(Telegram::ProcessMessageJob)
      .with(hash_including(photo: hash_including(file_id: "large_456", caption: nil)))
  end

  it "returns bad_request when Telegram update parsing raises a JSON error inside the action" do
    allow(Telegram::Bot::Types::Update).to receive(:new).and_raise(JSON::ParserError, "bad update")

    post webhook_path(connector.webhook_secret), params: payload.to_json, headers: json_headers

    expect(response).to have_http_status(:bad_request)
  end
end
