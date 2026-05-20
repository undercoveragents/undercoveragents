# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebFetch::PageExtractor do
  def response_class
    Struct.new(:uri, :body, :content_type, :truncated, keyword_init: true)
  end

  def fallback_html_response
    response_class.new(
      uri: "https://foo/path",
      content_type: "text/html",
      truncated: false,
      body: <<~HTML,
        <html>
          <head>
            <title>Fallback Domain</title>
          </head>
          <body>
            <main>
              <p>#{"a" * 500}</p>
              <a href="http://[invalid">Broken Link</a>
              <a href="/docs">Docs</a>
            </main>
          </body>
        </html>
      HTML
    )
  end

  describe ".call" do
    it "handles fallback domains, invalid links, and long text blocks", :aggregate_failures do
      response = fallback_html_response
      extractor = described_class.new(response)
      allow(PublicSuffix).to receive(:domain).with("foo").and_raise(PublicSuffix::Error, "bad host")

      page = described_class.call(response)

      expect(page.title).to eq("Fallback Domain")
      expect(page.snippets.first).to end_with("... (truncated)")
      expect(page.links.map(&:url)).to eq(["https://foo/docs"])
      expect(extractor.send(:registrable_domain, "foo")).to eq("foo")
      expect(extractor.send(:same_site_link, URI.parse(response.uri), "/docs")).to eq("https://foo/docs")
      expect(extractor.send(:same_site_link, URI.parse(response.uri), "http://[invalid")).to be_nil
    end

    it "returns empty snippets for blank fallback text and handles plain text pages", :aggregate_failures do
      html_response = response_class.new(
        uri: "https://example.com",
        content_type: "text/html",
        truncated: false,
        body: "<html><body><main><a href=\"#skip\"></a></main></body></html>",
      )
      plain_text_response = response_class.new(
        uri: "https://example.com/notes.txt",
        content_type: "text/plain",
        truncated: false,
        body: "Line one.\n\nThis paragraph covers Rails configuration defaults in detail.",
      )
      extractor = described_class.new(html_response)

      expect(described_class.call(html_response).snippets).to eq([])
      expect(described_class.call(plain_text_response).content_type).to eq("text/plain")
      expect(extractor.send(:score_text, "short text", index: 0, heading: true)).to be > 0
      expect(extractor.send(:same_site_link, URI.parse(html_response.uri), "#skip")).to be_nil
    end

    it "falls back to root text when the page has no qualifying blocks" do
      response = response_class.new(
        uri: "https://example.com/tiny",
        content_type: "text/html",
        truncated: false,
        body: "<html><body><main>Short but still readable fallback text about Rails " \
              "configuration and setup.</main></body></html>",
      )

      page = described_class.call(response)

      expect(page.snippets.first).to include("Rails configuration and setup")
    end
  end
end
