# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::TelegramLinkRequest do
  let(:tenant) { create(:tenant) }
  let(:channel) { create(:channel, :telegram, tenant:) }
  let(:user) { create(:user, tenant:) }

  describe ".issue!" do
    it "creates a pending request and returns the raw token" do
      token = described_class.issue!(channel:, user:)

      expect(token).to be_present
      expect(described_class.find_by(channel:, user:)).to be_present
      expect(described_class.find_by_token(channel:, token:)).to eq(described_class.find_by(channel:, user:))
    end

    it "replaces an existing pending request for the same user and channel" do
      first_token = described_class.issue!(channel:, user:)
      second_token = described_class.issue!(channel:, user:)

      expect(first_token).not_to eq(second_token)
      expect(described_class.where(channel:, user:).count).to eq(1)
      expect(described_class.find_by_token(channel:, token: second_token)).to be_present
    end
  end

  describe ".pending_for" do
    it "indexes pending requests by channel id" do
      request = create(:telegram_link_request, channel:, user:)

      expect(described_class.pending_for(user:, channels: [channel])).to eq(channel.id => request)
    end
  end

  it "returns nil when the lookup token is blank" do
    expect(described_class.find_by_token(channel:, token: " ")).to be_nil
  end

  it "validates that the user belongs to the same tenant as the channel" do
    foreign_user = create(:user)
    request = build(:telegram_link_request, channel:, user: foreign_user)

    expect(request).not_to be_valid
    expect(request.errors[:user]).to include("must belong to the same tenant as the channel")
  end

  it "validates that the channel must be a Telegram channel" do
    non_telegram_channel = create(:channel, :api, tenant:)
    request = build(:telegram_link_request, channel: non_telegram_channel, user:)

    expect(request).not_to be_valid
    expect(request.errors[:channel]).to include("must be a Telegram channel")
  end
end
