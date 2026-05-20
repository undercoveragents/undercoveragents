# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebSearch::Client do
  let(:client) { described_class.new }
  let(:search_url) { "https://html.duckduckgo.com/html/?q=rails+guide&s=0" }
  let(:html_page_url) { "https://guides.rubyonrails.org/" }

  before do
    allow(Resolv).to receive(:getaddresses).and_return(["93.184.216.34"])
  end

  def stub_html_page(body:, url: html_page_url, headers: {})
    stub_request(:get, url)
      .to_return(
        status: 200,
        body:,
        headers: { "Content-Type" => "text/html" }.merge(headers),
      )
  end

  def stub_search_result(url:, body:)
    stub_request(:get, url)
      .to_return(status: 200, body:, headers: { "Content-Type" => "text/html" })
  end

  def html_page_body
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

  def expect_html_page_result(page)
    expect(page).to have_attributes(
      title: "Rails Guides",
      description: "Official Rails documentation",
      truncated: true,
    )
    expect(page.snippets.first).to include("deployment")
    expect(page.snippets).to include(a_string_including("deployment defaults"))
    expect(page.links.map(&:url)).to match_array(expected_same_site_links)
  end

  def expected_same_site_links
    [
      "https://guides.rubyonrails.org/getting_started.html",
      "https://guides.rubyonrails.org/active_record_basics.html",
    ]
  end

  describe "#search" do
    it "parses public DuckDuckGo results and filters unsafe targets", :aggregate_failures do
      stub_search_result(
        url: search_url,
        body: <<~HTML,
          <html>
            <body>
              <div class="result">
                <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fguides.rubyonrails.org%2F">Ruby on Rails Guides</a>
                <a class="result__url">guides.rubyonrails.org</a>
                <a class="result__snippet">Official Rails guides.</a>
              </div>
              <div class="result">
                <a class="result__a" href="//duckduckgo.com/l/?uddg=http%3A%2F%2F127.0.0.1%2Fsecret">Unsafe</a>
                <a class="result__snippet">Should be skipped.</a>
              </div>
            </body>
          </html>
        HTML
      )

      results = client.search(query: "rails guide", max_results: 5)

      expect(results.map(&:title)).to eq(["Ruby on Rails Guides"])
      expect(results.first.url).to eq("https://guides.rubyonrails.org/")
      expect(results.first.display_url).to eq("guides.rubyonrails.org")
      expect(results.first.snippet).to eq("Official Rails guides.")
    end

    it "uses the lite fallback selectors when needed", :aggregate_failures do
      stub_search_result(
        url: "https://html.duckduckgo.com/html/?q=rails+guide&s=10",
        body: <<~HTML,
          <html>
            <body>
              <table>
                <tr>
                  <td><a class="result-link" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fpost">Example Post</a></td>
                </tr>
                <tr>
                  <td class="result-snippet">Snippet text</td>
                </tr>
                <tr>
                  <td><span class="link-text">example.com/post</span></td>
                </tr>
              </table>
            </body>
          </html>
        HTML
      )

      results = client.search(query: "rails guide", page: 2, max_results: 1)

      expect(results.size).to eq(1)
      expect(results.first.title).to eq("Example Post")
      expect(results.first.url).to eq("https://example.com/post")
    end

    it "falls back to lite search result rows when standard result blocks are absent" do
      document = Nokogiri::HTML5(
        '<html><body><table><tr><td><a class="result-link" href="https://example.com/post">Example</a></td></tr></table></body></html>',
      )

      nodes = client.send(:search_result_nodes, document)

      expect(nodes.size).to eq(1)
    end

    it "rejects blank search queries" do
      expect do
        client.search(query: " ")
      end.to raise_error(WebSearch::Client::Error, "A search query is required.")
    end

    it "rejects unsupported search content types" do
      stub_request(:get, "https://html.duckduckgo.com/html/?q=rails+guide&s=0")
        .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      expect do
        client.search(query: "rails guide")
      end.to raise_error(WebSearch::Client::Error, "Unsupported content type: application/json.")
    end

    it "ignores malformed DuckDuckGo redirect hrefs" do
      allow(URI).to receive(:decode_www_form).and_raise(ArgumentError)

      expect(client.send(:unwrap_duckduckgo_url, "http://[invalid")).to be_nil
      expect(client.send(:duckduckgo_redirect_target, URI("https://duckduckgo.com/l/?uddg=ok"))).to be_nil
    end

    it "handles blank and direct redirect hrefs" do
      expect(client.send(:unwrap_duckduckgo_url, "")).to be_nil
      expect(client.send(:unwrap_duckduckgo_url, "https://example.com/post")).to eq("https://example.com/post")
      expect(client.send(:unwrap_duckduckgo_url, "https://duckduckgo.com/l/?foo=bar")).to be_nil
    end

    it "skips malformed result nodes when parsing search results" do
      html = <<~HTML
        <html>
          <body>
            <div class="result"><span>No link here</span></div>
            <div class="result"><a class="result__a" href="">Blank href</a></div>
          </body>
        </html>
      HTML

      expect(client.send(:parse_search_results, html, max_results: 5)).to eq([])
    end
  end

  describe "#read" do
    it "extracts focused snippets, same-site links, and truncation hints from HTML pages", :aggregate_failures do
      stub_html_page(body: html_page_body, headers: { "Content-Length" => "999999" })

      pages = client.read(urls: [html_page_url], focus: "Rails deployment defaults")

      expect(pages.size).to eq(1)
      expect_html_page_result(pages.first)
    end

    it "reads plain text pages" do
      stub_request(:get, "https://example.com/notes.txt")
        .to_return(
          status: 200,
          body: "Line one.\n\nThis paragraph contains the important explanation about Rails defaults and updates.",
          headers: { "Content-Type" => "text/plain" },
        )

      pages = client.read(urls: ["https://example.com/notes.txt"], focus: "Rails defaults")

      expect(pages.first.content_type).to eq("text/plain")
      expect(pages.first.snippets.first).to include("Rails defaults")
      expect(pages.first.links).to eq([])
    end

    it "falls back to root text when the page has no qualifying blocks" do
      stub_html_page(
        url: "https://example.com/tiny",
        body: <<~HTML,
          <html><body><main>Short but still readable fallback text about Rails configuration and setup.</main></body></html>
        HTML
      )

      page = client.read(urls: ["https://example.com/tiny"]).first

      expect(page.snippets.first).to include("Rails configuration and setup")
    end

    it "caps the number of URLs per read call" do
      expect do
        client.read(
          urls: [
            "https://a.example.com",
            "https://b.example.com",
            "https://c.example.com",
            "https://d.example.com",
          ],
        )
      end.to raise_error(WebSearch::Client::Error, "Read at most 3 URLs per call.")
    end

    it "rejects empty URL sets" do
      expect do
        client.read(urls: [])
      end.to raise_error(WebSearch::Client::Error, "Provide at least one URL to read.")
    end

    it "follows safe redirects and rejects redirect responses without locations" do
      stub_request(:get, "https://example.com/start")
        .to_return(status: 302, headers: { "Location" => "https://example.com/final" })
      stub_request(:get, "https://example.com/final")
        .to_return(
          status: 200,
          body: "<html><body><main><p>Final public page text about Rails upgrades.</p></main></body></html>",
          headers: { "Content-Type" => "text/html" },
        )

      page = client.read(urls: ["https://example.com/start"]).first
      expect(page.url).to eq("https://example.com/final")

      stub_request(:get, "https://example.com/missing-location")
        .to_return(status: 302, headers: {})

      expect do
        client.read(urls: ["https://example.com/missing-location"])
      end.to raise_error(WebSearch::Client::Error, "Redirect response did not include a location.")
    end

    it "raises on request failures and unsafe responses" do
      stub_request(:get, "https://example.com/failure").to_return(status: 500, body: "boom")
      expect do
        client.read(urls: ["https://example.com/failure"])
      end.to raise_error(WebSearch::Client::Error, "HTTP request failed with status 500.")

      stub_request(:get, "https://example.com/private-redirect")
        .to_return(status: 302, headers: { "Location" => "http://127.0.0.1/private" })
      expect do
        client.read(urls: ["https://example.com/private-redirect"])
      end.to raise_error(WebSearch::Safety::Error, "Local or private network targets are not allowed.")

      stub_request(:get, "https://example.com/loop")
        .to_return(status: 302, headers: { "Location" => "https://example.com/loop" })
      expect do
        client.read(urls: ["https://example.com/loop"])
      end.to raise_error(WebSearch::Client::Error, "Too many redirects.")

      stub_request(:get, "https://example.com/binary")
        .to_return(status: 200, body: "%PDF", headers: { "Content-Type" => "application/pdf" })
      expect do
        client.read(urls: ["https://example.com/binary"])
      end.to raise_error(WebSearch::Client::Error, "Unsupported content type: application/pdf.")

      allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(Net::ReadTimeout) # rubocop:disable RSpec/AnyInstance
      expect do
        client.read(urls: ["https://example.com/network-timeout"])
      end.to raise_error(WebSearch::Client::Error, /Network request failed/)
    end

    it "marks reads truncated when the body reaches the byte cap during streaming" do
      response = instance_double(Net::HTTPOK)
      body = +""
      payload = { truncated: false }

      allow(response).to receive(:read_body).and_yield("abcdef")
      client.send(:read_capped_body, response, body, max_bytes: 3, payload:)

      expect(body).to eq("abc")
      expect(payload[:truncated]).to be(true)
    end

    it "marks reads truncated when additional chunks arrive after the byte cap" do
      response = instance_double(Net::HTTPOK)
      body = +"abc"
      payload = { truncated: false }

      allow(response).to receive(:read_body).and_yield("z")
      client.send(:read_capped_body, response, body, max_bytes: 3, payload:)

      expect(body).to eq("abc")
      expect(payload[:truncated]).to be(true)
    end

    it "normalizes raw URLs and handles nil responses" do
      response = instance_double(Net::HTTPOK, code: "200")
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(client).to receive_messages(
        perform_request: { response:, body: "ok", truncated: false },
        content_length_exceeded?: false,
        redirect_response?: false,
        normalized_content_type: "text/plain",
      )

      result = client.send(
        :fetch_text,
        "https://example.com/notes.txt",
        max_bytes: 5,
        allowed_content_types: WebSearch::Client::ALLOWED_PAGE_CONTENT_TYPES,
      )
      expect(result.uri).to eq("https://example.com/notes.txt")

      expect do
        client.send(
          :finalize_response,
          uri: URI("https://example.com"),
          payload: { response: nil, body: "", truncated: false },
          request_options: { max_bytes: 1, allowed_content_types: [] },
          redirects_remaining: 1,
        )
      end.to raise_error(WebSearch::Client::Error, "No HTTP response was received.")
    end

    it "sets write timeout only when the HTTP client supports it" do
      http = instance_double(Net::HTTP)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:respond_to?).with(:write_timeout=).and_return(false)
      allow(Net::HTTP).to receive(:new).and_return(http)

      client.send(:http_client_for, URI("https://example.com"))

      expect(http).not_to have_received(:write_timeout=)
    end
  end
end
