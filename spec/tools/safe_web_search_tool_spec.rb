# frozen_string_literal: true

require "rails_helper"

RSpec.describe SafeWebSearchTool do
  let(:client) { instance_double(WebSearch::Client) }
  let(:tool) { described_class.new(client:) }

  def page_result
    WebSearch::Client::PageResult.new(
      url: "https://guides.rubyonrails.org/",
      title: "Rails Guides",
      description: "Official docs",
      snippets: ["Important snippet"],
      links: [
        WebSearch::Client::RelatedLink.new(
          text: "Getting Started",
          url: "https://guides.rubyonrails.org/getting_started.html",
        ),
      ],
      content_type: "text/html",
      truncated: true,
    )
  end

  describe "#name" do
    it "returns the runtime tool name" do
      expect(tool.name).to eq("safe_web_search")
    end
  end

  describe "#execute" do
    it "formats search results" do
      result = WebSearch::Client::SearchResult.new(
        title: "Rails Guides",
        url: "https://guides.rubyonrails.org/",
        display_url: "guides.rubyonrails.org",
        snippet: "Official Rails documentation.",
      )
      allow(client).to receive(:search).with(query: "rails guide", page: 2, max_results: 3).and_return([result])

      response = tool.execute(action: "search", query: "rails guide", page: 2, max_results: 3)

      expect(response).to include("Search query: rails guide")
      expect(response).to include("Page: 2")
      expect(response).to include("1. Rails Guides")
      expect(response).to include("URL: https://guides.rubyonrails.org/")
      expect(response).to include('call safe_web_search with action="read"')
    end

    it "formats empty search results" do
      allow(client).to receive(:search).with(query: "rails guide", page: nil, max_results: nil).and_return([])

      response = tool.execute(action: "search", query: "rails guide")

      expect(response).to include("Results: 0")
      expect(response).to include("No public search results were returned.")
    end

    it "omits optional search-result lines when display metadata is blank" do
      allow(client).to receive(:search).and_return(
        [
          WebSearch::Client::SearchResult.new(
            title: "Plain Result",
            url: "https://example.com",
            display_url: nil,
            snippet: "",
          ),
        ],
      )

      response = tool.execute(action: "search", query: "plain")

      expect(response).to include("Plain Result")
      expect(response).not_to include("Site:")
      expect(response).not_to include("Snippet:")
    end

    it "formats page reads and flattened URL inputs" do
      allow(client).to receive(:read)
        .with(
          urls: [
            "https://guides.rubyonrails.org/",
            "https://guides.rubyonrails.org/getting_started.html",
          ],
          focus: "defaults",
        )
        .and_return([page_result])

      response = tool.execute(
        action: "read",
        url: "https://guides.rubyonrails.org/",
        urls: ["https://guides.rubyonrails.org/getting_started.html"],
        focus: "defaults",
      )

      expect(response).to include("Focus: defaults")
      expect(response).to include("Pages read: 1")
      expect(response).to include("Title: Rails Guides")
      expect(response).to include("Fetched only the initial capped page content.")
      expect(response).to include("- Getting Started: https://guides.rubyonrails.org/getting_started.html")
    end

    it "formats page reads with no snippets or links" do
      allow(client).to receive(:read).and_return(
        [
          WebSearch::Client::PageResult.new(
            url: "https://example.com",
            title: "",
            description: "",
            snippets: [],
            links: [],
            content_type: "text/html",
            truncated: false,
          ),
        ],
      )

      response = tool.execute(action: "read", url: "https://example.com")

      expect(response).to include("Relevant snippets: none extracted.")
      expect(response).not_to include("Related same-site links:")
    end

    it "returns a clear error for unsupported actions" do
      expect(tool.execute(action: "unknown")).to include("Unknown action")
    end

    it "surfaces safety and client failures" do
      allow(client).to receive(:search).and_raise(WebSearch::Client::Error, "boom")
      expect(tool.execute(action: "search", query: "rails")).to eq("Web search failed: boom")

      allow(client).to receive(:read).and_raise(WebSearch::Safety::Error, "unsafe")
      expect(tool.execute(action: "read", url: "https://example.com")).to eq("Web search failed: unsafe")
    end
  end
end
