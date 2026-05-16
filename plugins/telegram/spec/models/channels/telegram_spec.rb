# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::Telegram do
  let(:tenant) { create(:tenant) }
  let(:connector) { create(:connector, :telegram, tenant:) }

  def build_configurator(channel:)
    described_class.new(channel.configuration).tap do |configurator|
      configurator._channel_record = channel
    end
  end

  it "is valid with a Telegram connector" do
    channel = build(:channel, :telegram, tenant:, connector:)

    expect(build_configurator(channel:)).to be_valid
  end

  it "requires a connector" do
    channel = build(:channel, :telegram, tenant:, connector: nil)
    configurator = build_configurator(channel:)

    expect(configurator).not_to be_valid
    expect(configurator.errors[:connector]).to include("is required")
  end

  it "rejects connector reuse across Telegram channels" do
    create(:channel, :telegram, tenant:, connector:)
    channel = build(:channel, :telegram, tenant:, connector:)
    configurator = build_configurator(channel:)

    expect(configurator).not_to be_valid
    expect(configurator.errors[:connector]).to include("is already assigned to another Telegram channel")
  end

  it "builds summaries with the bot username and streaming mode" do
    channel = build(
      :channel,
      :telegram,
      tenant:,
      connector: create(:connector, :telegram, tenant:, bot_username: "ops_bot"),
      configuration: {
        "welcome_message" => Channels::Telegram::DEFAULT_WELCOME_MESSAGE,
        "max_history_messages" => Channels::Telegram::DEFAULT_MAX_HISTORY,
        "streaming_enabled" => false,
      },
    )
    configurator = build_configurator(channel:)

    expect(configurator.summary).to eq("@ops_bot / Final only")
  end

  it "omits the username from the summary when the connector has not fetched it yet" do
    blank_username_connector = create(:connector, :telegram, tenant:, bot_username: nil)
    channel = build(:channel, :telegram, tenant:, connector: blank_username_connector)
    configurator = build_configurator(channel:)

    expect(configurator.summary).to eq("Streaming")
  end

  it "falls back to the streaming mode when no channel record is attached" do
    expect(described_class.new.summary).to eq("Streaming")
  end

  it "validates cleanly when detached from a channel record" do
    configurator = described_class.new

    expect(configurator).not_to be_valid
    expect(configurator.errors[:connector]).to include("is required")
  end

  it "allows unpersisted channel-like records during connector reuse checks" do
    channel_record = Struct.new(:connector, :connector_id, :persisted?, :id).new(connector, connector.id, false, nil)
    configurator = described_class.new
    configurator._channel_record = channel_record

    expect(configurator).to be_valid
  end

  it "treats a missing channel record as not persisted" do
    expect(described_class.new.send(:persisted_channel_record?, nil)).to be(false)
  end

  it "allows an existing Telegram channel to keep its current connector" do
    channel = create(:channel, :telegram, tenant:, connector:)

    expect(build_configurator(channel:)).to be_valid
  end
end
