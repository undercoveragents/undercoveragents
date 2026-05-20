# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebSearch::SearchService do
  describe "#search" do
    it "normalizes query, page, and result limits before delegating" do
      client = instance_double(WebSearch::Clients::DuckDuckGoClient)
      allow(client).to receive(:search).and_return([])

      described_class.new(client:).search(query: " rails guide ", page: 99, max_results: 99)

      expect(client).to have_received(:search).with(query: "rails guide", page: 5, max_results: 8)
    end

    it "resolves the configured provider through the registry" do
      client = instance_double(WebSearch::Clients::DuckDuckGoClient, search: [])
      allow(WebSearch::SearchClientRegistry).to receive(:fetch).with("duckduckgo").and_return(client)

      described_class.new(provider: "duckduckgo").search(query: "rails")

      expect(client).to have_received(:search).with(query: "rails", page: 1, max_results: 5)
    end
  end
end
