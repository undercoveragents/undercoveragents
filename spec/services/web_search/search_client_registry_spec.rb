# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebSearch::SearchClientRegistry do
  around do |example|
    described_class.reset!
    described_class.register("duckduckgo", "WebSearch::Clients::DuckDuckGoClient", default: true)
    example.run
  ensure
    described_class.reset!
    described_class.register("duckduckgo", "WebSearch::Clients::DuckDuckGoClient", default: true)
  end

  describe ".fetch" do
    it "returns the default registered client" do
      expect(described_class.default_identifier).to eq("duckduckgo")
      expect(described_class.registered?("duckduckgo")).to be(true)
      expect(described_class.fetch).to be_a(WebSearch::Clients::DuckDuckGoClient)
    end

    it "raises for unknown providers" do
      expect do
        described_class.fetch("missing")
      end.to raise_error(WebSearch::Error, "Unknown web search client: missing.")
    end
  end

  describe ".register" do
    it "keeps the current default when registering a non-default client" do
      described_class.register("secondary", "WebSearch::Clients::DuckDuckGoClient")

      expect(described_class.default_identifier).to eq("duckduckgo")
      expect(described_class.fetch("secondary")).to be_a(WebSearch::Clients::DuckDuckGoClient)
    end

    it "rejects conflicting registrations" do
      expect do
        described_class.register("duckduckgo", "String")
      end.to raise_error(ArgumentError, 'Search client "duckduckgo" is already registered.')
    end
  end
end
