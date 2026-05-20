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

  describe "#read" do
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
      end.to raise_error(WebFetch::Error, "HTTP request failed with status 500.")
    end
  end
end
