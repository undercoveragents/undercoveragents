# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cloud::PendingSignup do
  describe ".load" do
    it "returns the stored provider entry" do
      session = {
        described_class::SESSION_KEY => {
          "provider" => "google",
        },
      }

      expect(described_class.load(session)).to eq(described_class::Entry.new(provider: "google"))
    end

    it "returns nil when the stored payload is incomplete" do
      session = {
        described_class::SESSION_KEY => {
          "provider" => "",
        },
      }

      expect(described_class.load(session)).to be_nil
    end
  end

  describe ".from_request_params" do
    it "returns the onboarding provider when the request matches the hosted signup flow" do
      params = {
        described_class::REQUEST_PARAM_KEY => {
          "flow" => described_class::FLOW,
        },
      }

      expect(described_class.from_request_params(params)).to eq(described_class::Entry.new(provider: "google"))
    end

    it "returns nil when the request is not a tenant-onboarding flow" do
      params = {
        described_class::REQUEST_PARAM_KEY => {
          "flow" => "other",
        },
      }

      expect(described_class.from_request_params(params)).to be_nil
    end

    it "returns nil when the request has no hosted signup payload" do
      expect(described_class.from_request_params({})).to be_nil
    end
  end
end
