# frozen_string_literal: true

require "rails_helper"

RSpec.describe SafeWebSearchTool do
  let(:service) { instance_double(WebSearch::SearchService) }
  let(:tool) { described_class.new(service:) }

  describe "#name" do
    it "returns the runtime tool name" do
      expect(tool.name).to eq("safe_web_search")
    end
  end

  describe "#execute" do
    it "formats search results" do
      result = WebSearch::SearchResult.new(
        title: "Rails Guides",
        url: "https://guides.rubyonrails.org/",
        display_url: "guides.rubyonrails.org",
        snippet: "Official Rails documentation.",
      )
      allow(service).to receive(:search).with(query: "rails guide", page: 2, max_results: 3).and_return([result])

      response = tool.execute(query: "rails guide", page: 2, max_results: 3)

      expect(response).to include("Search query: rails guide")
      expect(response).to include("Page: 2")
      expect(response).to include("1. Rails Guides")
      expect(response).to include("URL: https://guides.rubyonrails.org/")
      expect(response).to include("call web_fetch")
    end

    it "formats empty search results" do
      allow(service).to receive(:search).with(query: "rails guide", page: nil, max_results: nil).and_return([])

      response = tool.execute(query: "rails guide")

      expect(response).to include("Results: 0")
      expect(response).to include("No public search results were returned.")
    end

    it "omits optional search-result lines when display metadata is blank" do
      allow(service).to receive(:search).and_return(
        [
          WebSearch::SearchResult.new(
            title: "Plain Result",
            url: "https://example.com",
            display_url: nil,
            snippet: "",
          ),
        ],
      )

      response = tool.execute(query: "plain")

      expect(response).to include("Plain Result")
      expect(response).not_to include("Site:")
      expect(response).not_to include("Snippet:")
    end

    it "uses the provider override when requested" do
      provider_service = instance_double(WebSearch::SearchService, search: [])
      allow(WebSearch::SearchService).to receive(:new).with(provider: "duckduckgo").and_return(provider_service)

      tool.execute(query: "rails", provider: "duckduckgo")

      expect(provider_service).to have_received(:search).with(query: "rails", page: nil, max_results: nil)
    end

    it "surfaces service failures" do
      allow(service).to receive(:search).and_raise(WebSearch::Error, "boom")

      expect(tool.execute(query: "rails")).to eq("Web search failed: boom")
    end
  end
end
