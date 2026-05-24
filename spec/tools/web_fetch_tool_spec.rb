# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebFetchTool do
  let(:client) { instance_double(WebFetch::Client) }
  let(:tool) { described_class.new(client:) }

  def page_result
    WebFetch::PageResult.new(
      url: "https://guides.rubyonrails.org/",
      title: "Rails Guides",
      description: "Official docs",
      snippets: ["Important snippet"],
      links: [
        WebFetch::RelatedLink.new(
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
      expect(tool.name).to eq("web_fetch")
    end
  end

  describe "#execute" do
    it "formats fetched page results" do
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

    it "formats pages without snippets or related links" do
      allow(client).to receive(:read).and_return(
        [
          WebFetch::PageResult.new(
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

      response = tool.execute(url: "https://example.com")

      expect(response).to include("Relevant snippets: none extracted.")
      expect(response).not_to include("Related same-site links:")
    end

    it "surfaces fetch failures" do
      allow(client).to receive(:read).and_raise(WebFetch::Error, "Failed to fetch https://example.com: boom")

      expect(tool.execute(url: "https://example.com")).to eq(
        "Web fetch failed: Failed to fetch https://example.com: boom",
      )
    end
  end
end
