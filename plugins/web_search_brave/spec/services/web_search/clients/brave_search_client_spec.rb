# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebSearch::Clients::BraveSearchClient do
  let(:connector) { build(:connectors_brave_search, api_key: "brave-test-key") }
  let(:client) { described_class.new(connector:) }

  before do
    allow(Resolv).to receive(:getaddresses).and_return(["93.184.216.34"])
  end

  def stub_brave_search(query:, max_results:, body:)
    stub_request(
      :get,
      "https://api.search.brave.com/res/v1/web/search?count=#{max_results}&offset=0&q=#{query}",
    ).with(headers: { "X-Subscription-Token" => "brave-test-key", "Accept" => "application/json" })
      .to_return(status: 200, body:, headers: { "Content-Type" => "application/json" })
  end

  def brave_results_body
    {
      web: {
        results: [
          {
            title: "Ruby on Rails Guides",
            url: "https://guides.rubyonrails.org/",
            description: "Official Rails guides.",
            meta_url: { hostname: "guides.rubyonrails.org" },
          },
          {
            title: "Unsafe Result",
            url: "http://127.0.0.1/secret",
            description: "Should be skipped.",
          },
        ],
      },
    }.to_json
  end

  describe "#search" do
    it "parses Brave results and filters unsafe targets", :aggregate_failures do
      stub_brave_search(query: "rails+guide", max_results: 5, body: brave_results_body)

      results = client.search(query: "rails guide", page: 1, max_results: 5)

      expect(results.map(&:title)).to eq(["Ruby on Rails Guides"])
      expect(results.first.url).to eq("https://guides.rubyonrails.org/")
      expect(results.first.display_url).to eq("guides.rubyonrails.org")
      expect(results.first.snippet).to eq("Official Rails guides.")
    end

    it "rejects blank queries and invalid JSON" do
      expect do
        client.search(query: " ", page: 1, max_results: 1)
      end.to raise_error(WebSearch::Error, "A search query is required.")

      stub_brave_search(query: "rails", max_results: 1, body: "{not-json")

      expect do
        client.search(query: "rails", page: 1, max_results: 1)
      end.to raise_error(WebSearch::Error, "Brave Search returned an invalid JSON response.")
    end

    it "raises when the connector is missing" do
      missing_connector_class = class_double(Connectors::BraveSearch, current_connector: nil)
      missing_connector_client = described_class.new(connector_class: missing_connector_class)

      expect do
        missing_connector_client.search(query: "rails", page: 1, max_results: 1)
      end.to raise_error(
        WebSearch::Error,
        "Brave Search requires an enabled Brave Search connector for the current tenant.",
      )
    end

    it "surfaces credential decryption failures" do
      broken_connector = instance_double(Connectors::BraveSearch)
      allow(broken_connector).to receive(:api_key).and_raise(ActiveRecord::Encryption::Errors::Decryption)
      broken_client = described_class.new(connector: broken_connector)

      expect do
        broken_client.search(query: "rails", page: 1, max_results: 1)
      end.to raise_error(
        WebSearch::Error,
        "Cannot decrypt Brave Search credentials. Re-enter the API key in the Brave Search connector settings.",
      )
    end

    it "skips results without URLs and tolerates invalid display URL parsing" do
      stub_brave_search(
        query: "rails",
        max_results: 2,
        body: {
          web: {
            results: [
              { title: "Blank URL", url: "" },
              { title: "Example", url: "https://example.com/articles/1", description: "Example result." },
            ],
          },
        }.to_json,
      )

      results = client.search(query: "rails", page: 1, max_results: 2)

      expect(results.map(&:title)).to eq(["Example"])
      expect(client.send(:display_url_for, {}, "https://[invalid")).to be_nil
    end
  end
end
