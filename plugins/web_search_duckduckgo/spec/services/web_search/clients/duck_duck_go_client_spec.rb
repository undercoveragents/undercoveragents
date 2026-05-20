# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebSearch::Clients::DuckDuckGoClient do
  let(:client) { described_class.new }

  before do
    allow(Resolv).to receive(:getaddresses).and_return(["93.184.216.34"])
  end

  def lite_results_body
    <<~HTML
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
  end

  def stub_lite_results_page
    stub_request(:get, "https://html.duckduckgo.com/html/?q=rails+guide&s=10")
      .to_return(
        status: 200,
        body: lite_results_body,
        headers: { "Content-Type" => "text/html" },
      )
  end

  describe "#search" do
    it "parses public DuckDuckGo results and filters unsafe targets", :aggregate_failures do
      stub_request(:get, "https://html.duckduckgo.com/html/?q=rails+guide&s=0")
        .to_return(
          status: 200,
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
          headers: { "Content-Type" => "text/html" },
        )

      results = client.search(query: "rails guide", page: 1, max_results: 5)

      expect(results.map(&:title)).to eq(["Ruby on Rails Guides"])
      expect(results.first.url).to eq("https://guides.rubyonrails.org/")
      expect(results.first.display_url).to eq("guides.rubyonrails.org")
      expect(results.first.snippet).to eq("Official Rails guides.")
    end

    it "uses the lite fallback selectors when needed", :aggregate_failures do
      stub_lite_results_page

      results = client.search(query: "rails guide", page: 2, max_results: 1)

      expect(results.size).to eq(1)
      expect(results.first.title).to eq("Example Post")
      expect(results.first.url).to eq("https://example.com/post")
    end

    it "rejects blank queries and ignores malformed redirect hrefs" do
      expect do
        client.search(query: " ", page: 1, max_results: 1)
      end.to raise_error(WebSearch::Error, "A search query is required.")

      allow(URI).to receive(:decode_www_form).and_raise(ArgumentError)

      expect(client.send(:unwrap_duckduckgo_url, "http://[invalid")).to be_nil
      expect(client.send(:duckduckgo_redirect_target, URI("https://duckduckgo.com/l/?uddg=ok"))).to be_nil
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
      expect(client.send(:unwrap_duckduckgo_url, "https://example.com/post")).to eq("https://example.com/post")
      expect(client.send(:unwrap_duckduckgo_url, "https://duckduckgo.com/l/?foo=bar")).to be_nil
    end
  end
end
