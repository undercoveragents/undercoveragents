# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatStreamChannel do
  let(:user) { create(:user, :admin) }
  let(:stream_name) { Chat.user_stream_channel_name_for(user) }
  let(:stream_token) { Chat.signed_stream_name(stream_name) }

  describe "#subscribed" do
    it "subscribes to the verified chat stream" do
      subscribe(stream_token:)

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from(stream_name)
    end
  end

  describe "#subscribed with an invalid token" do
    it "rejects the subscription" do
      subscribe(stream_token: "invalid")

      expect(subscription).to be_rejected
    end
  end

  describe "#subscribed when verification raises" do
    it "rejects the subscription" do
      allow(Chat).to receive(:verified_stream_name).and_raise(ActiveSupport::MessageVerifier::InvalidSignature)

      subscribe(stream_token: "tampered")

      expect(subscription).to be_rejected
    end
  end

  describe "#unsubscribed" do
    it "stops all streams on unsubscribe" do
      subscribe(stream_token:)
      unsubscribe

      expect(subscription).not_to have_streams
    end
  end
end
