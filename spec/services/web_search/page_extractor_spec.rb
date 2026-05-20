# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebSearch::PageExtractor do
  def response_class
    Struct.new(:uri, :body, :content_type, :truncated, keyword_init: true)
  end

  def html_response
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
      response = html_response
      page = described_class.call(response)
      extractor = described_class.new(response)
      allow(PublicSuffix).to receive(:domain).with("foo").and_raise(PublicSuffix::Error, "bad host")

      expect(page.title).to eq("Fallback Domain")
      expect(page.snippets.first).to end_with("... (truncated)")
      expect(page.links).to eq([])
      expect(extractor.send(:registrable_domain, "foo")).to eq("foo")
      expect(extractor.send(:same_site_link, URI.parse(response.uri), "/docs")).to eq("https://foo/docs")
      expect(extractor.send(:same_site_link, URI.parse(response.uri), "http://[invalid")).to be_nil
    end

    it "returns empty snippets when fallback text is blank and covers skipped link branches", :aggregate_failures do
      response = response_class.new(
        uri: "https://example.com",
        content_type: "text/html",
        truncated: false,
        body: "<html><body><main><a href=\"#skip\"></a></main></body></html>",
      )
      extractor = described_class.new(response)

      expect(described_class.call(response).snippets).to eq([])
      expect(extractor.send(:score_text, "short text", index: 0, heading: true)).to be > 0
      expect(extractor.send(:same_site_link, URI.parse(response.uri), "#skip")).to be_nil
    end
  end
end
