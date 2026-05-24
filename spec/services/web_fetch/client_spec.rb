# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebFetch::Client do
  let(:client) { described_class.new }

  before do
    allow(Resolv).to receive(:getaddresses).and_return(["93.184.216.34"])
  end

  def guides_page_body
    <<~HTML
      <html>
        <head>
          <title>Rails Guides</title>
          <meta name="description" content="Official Rails documentation">
        </head>
        <body>
          <main>
            <h1>Rails Guides</h1>
            <p>Rails 8.1 adds new defaults for modern app development and deployment.</p>
            <p>This paragraph talks about routing, authentication, and deployment defaults.</p>
            <a href="/getting_started.html">Getting Started</a>
            <a href="https://guides.rubyonrails.org/active_record_basics.html">Active Record Basics</a>
            <a href="https://external.example.com/other">External</a>
          </main>
        </body>
      </html>
    HTML
  end

  def stub_guides_page
    stub_request(:get, "https://guides.rubyonrails.org/")
      .to_return(
        status: 200,
        body: guides_page_body,
        headers: { "Content-Type" => "text/html", "Content-Length" => "999999" },
      )
  end

  def http_response_for(uri:, body: guides_page_body, content_type: "text/html", truncated: false)
    WebSearch::HttpClient::Response.new(
      uri: uri.to_s,
      body:,
      content_type:,
      truncated:,
    )
  end

  def request_options(headers:, range_request:)
    {
      max_bytes: described_class::MAX_PAGE_BYTES,
      allowed_content_types: described_class::ALLOWED_PAGE_CONTENT_TYPES,
      headers:,
      range_request:,
    }
  end

  def build_client_with_http_spy(url)
    http_client = instance_spy(WebSearch::HttpClient)
    uri = URI(url)
    allow(WebSearch::Safety).to receive(:validate_public_url!).with(url).and_return(uri)

    [described_class.new(http_client:), http_client, uri]
  end

  def expect_guides_page(page)
    expect(page.title).to eq("Rails Guides")
    expect(page.snippets.first).to include("deployment")
  end

  describe "#read" do
    it "tries identity encoding first and falls back to the default request" do
      client, http_client, uri = build_client_with_http_spy("https://example.com/page")
      allow(http_client).to receive(:fetch_text)
        .with(uri, **request_options(headers: described_class::IDENTITY_ENCODING_HEADERS, range_request: true))
        .and_raise(WebSearch::Error, "Network request failed: end of file reached")
      allow(http_client).to receive(:fetch_text)
        .with(uri, **request_options(headers: {}, range_request: true))
        .and_return(http_response_for(uri:))

      page = client.read(urls: ["https://example.com/page"], focus: "Rails deployment defaults").first

      expect_guides_page(page)
      expect(http_client).to have_received(:fetch_text)
        .with(uri, **request_options(headers: described_class::IDENTITY_ENCODING_HEADERS, range_request: true))
      expect(http_client).to have_received(:fetch_text)
        .with(uri, **request_options(headers: {}, range_request: true))
    end

    it "retries without the range header after network failures" do
      client, http_client, uri = build_client_with_http_spy("https://example.com/page")
      allow(http_client).to receive(:fetch_text)
        .with(uri, **request_options(headers: described_class::IDENTITY_ENCODING_HEADERS, range_request: true))
        .and_raise(WebSearch::Error, "Network request failed: end of file reached")
      allow(http_client).to receive(:fetch_text)
        .with(uri, **request_options(headers: {}, range_request: true))
        .and_raise(WebSearch::Error, "Network request failed: wrong chunk size line")
      allow(http_client).to receive(:fetch_text)
        .with(uri, **request_options(headers: {}, range_request: false))
        .and_return(http_response_for(uri:))

      page = client.read(urls: ["https://example.com/page"], focus: "Rails deployment defaults").first

      expect_guides_page(page)
      expect(http_client).to have_received(:fetch_text)
        .with(uri, **request_options(headers: described_class::IDENTITY_ENCODING_HEADERS, range_request: true))
      expect(http_client).to have_received(:fetch_text)
        .with(uri, **request_options(headers: {}, range_request: true))
      expect(http_client).to have_received(:fetch_text)
        .with(uri, **request_options(headers: {}, range_request: false))
    end

    it "extracts focused snippets, same-site links, and truncation hints from HTML pages", :aggregate_failures do
      stub_guides_page

      page = client.read(urls: ["https://guides.rubyonrails.org/"], focus: "Rails deployment defaults").first

      expect(page.title).to eq("Rails Guides")
      expect(page.description).to eq("Official Rails documentation")
      expect(page.snippets.first).to include("deployment")
      expect(page.links.map(&:url)).to contain_exactly(
        "https://guides.rubyonrails.org/getting_started.html",
        "https://guides.rubyonrails.org/active_record_basics.html",
      )
      expect(page.truncated).to be(true)
    end

    it "reads plain text pages" do
      stub_request(:get, "https://example.com/notes.txt")
        .to_return(
          status: 200,
          body: "Line one.\n\nThis paragraph contains the important explanation about Rails defaults and updates.",
          headers: { "Content-Type" => "text/plain" },
        )

      page = client.read(urls: ["https://example.com/notes.txt"], focus: "Rails defaults").first

      expect(page.content_type).to eq("text/plain")
      expect(page.snippets.first).to include("Rails defaults")
      expect(page.links).to eq([])
    end

    it "validates URL count and wraps HTTP errors" do
      expect do
        client.read(
          urls: ["https://a.example.com", "https://b.example.com", "https://c.example.com", "https://d.example.com"],
        )
      end.to raise_error(WebFetch::Error, "Read at most 3 URLs per call.")

      expect do
        client.read(urls: [])
      end.to raise_error(WebFetch::Error, "Provide at least one URL to read.")

      stub_request(:get, "https://example.com/failure").to_return(status: 500, body: "boom")

      expect do
        client.read(urls: ["https://example.com/failure"])
      end.to raise_error(
        WebFetch::Error,
        "Failed to fetch https://example.com/failure: HTTP request failed with status 500.",
      )
    end
  end
end
