# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telegram::WebhookSetupService do
  let(:tenant) { create(:tenant) }
  let(:connector) { create(:connector, :telegram, tenant:) }
  let(:channel) { create(:channel, :telegram, tenant:, connector:) }

  it "registers a webhook for a Telegram channel" do
    allow(connector).to receive(:register_webhook!) do |_url, secret:|
      connector.webhook_secret = secret
    end
    allow(connector).to receive(:save!).and_return(true)

    result = described_class.new(channel, host: "app.example.test").call

    expect(result.success?).to be(true)
    expect(result.message).to eq(I18n.t("channels.telegram.webhook_registered"))
    expect(connector).to have_received(:register_webhook!).with(
      a_string_matching(%r{http://app\.example\.test/channels/telegram/#{channel.to_param}/webhook/}),
      secret: kind_of(String),
    )
  end

  it "uses the TELEGRAM_WEBHOOK_BASE_URL override when present" do
    allow(connector).to receive(:register_webhook!) do |_url, secret:|
      connector.webhook_secret = secret
    end
    allow(connector).to receive(:save!).and_return(true)

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("TELEGRAM_WEBHOOK_BASE_URL").and_return("https://my-ngrok.example.com")

    described_class.new(channel).call

    expect(connector).to have_received(:register_webhook!).with(
      "https://my-ngrok.example.com/channels/telegram/#{channel.to_param}/webhook/#{connector.webhook_secret}",
      secret: connector.webhook_secret,
    )
  end

  it "returns a failure result for non-Telegram channels" do
    api_channel = create(:channel, :api, tenant:, connector: nil)

    result = described_class.new(api_channel).call

    expect(result.success?).to be(false)
    expect(result.message).to eq(I18n.t("channels.telegram.not_telegram"))
  end

  it "returns a failure result when a Telegram channel has no connector" do
    connectorless_channel = build(:channel, :telegram, tenant:, connector: nil)

    result = described_class.new(connectorless_channel).call

    expect(result.success?).to be(false)
    expect(result.message).to eq(I18n.t("channels.telegram.not_telegram"))
  end

  it "returns a failure result when webhook registration raises" do
    allow(connector).to receive(:register_webhook!).and_raise(StandardError, "boom")

    result = described_class.new(channel, host: "app.example.test").call

    expect(result.success?).to be(false)
    expect(result.message).to include("boom")
  end
end
