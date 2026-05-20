# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebSearch::HttpClient do
  let(:client) { described_class.new }

  before do
    allow(Resolv).to receive(:getaddresses).and_return(["93.184.216.34"])
  end

  describe "#fetch_text" do
    it "follows safe redirects and returns the final public response", :aggregate_failures do
      stub_request(:get, "https://example.com/start")
        .to_return(status: 302, headers: { "Location" => "https://example.com/final" })
      stub_request(:get, "https://example.com/final")
        .to_return(
          status: 200,
          body: "<html><body><main><p>Final public page text about Rails upgrades.</p></main></body></html>",
          headers: { "Content-Type" => "text/html", "Content-Length" => "999999" },
        )

      response = client.fetch_text(
        "https://example.com/start",
        max_bytes: 100,
        allowed_content_types: ["text/html"],
      )

      expect(response.uri).to eq("https://example.com/final")
      expect(response.content_type).to eq("text/html")
      expect(response.body).to include("Final public page text")
      expect(response.truncated).to be(true)
    end

    it "raises for redirects without locations" do
      stub_request(:get, "https://example.com/missing-location").to_return(status: 302, headers: {})

      expect do
        client.fetch_text("https://example.com/missing-location", max_bytes: 50, allowed_content_types: ["text/html"])
      end.to raise_error(WebSearch::Error, "Redirect response did not include a location.")
    end

    it "raises for too many redirects" do
      stub_request(:get, "https://example.com/loop")
        .to_return(status: 302, headers: { "Location" => "https://example.com/loop" })

      expect do
        client.fetch_text("https://example.com/loop", max_bytes: 50, allowed_content_types: ["text/html"])
      end.to raise_error(WebSearch::Error, "Too many redirects.")
    end

    it "rejects unsupported content types" do
      stub_request(:get, "https://example.com/binary")
        .to_return(status: 200, body: "%PDF", headers: { "Content-Type" => "application/pdf" })

      expect do
        client.fetch_text("https://example.com/binary", max_bytes: 50, allowed_content_types: ["text/html"])
      end.to raise_error(WebSearch::Error, "Unsupported content type: application/pdf.")
    end

    it "raises for missing responses and request failures" do
      expect do
        client.send(
          :finalize_response,
          uri: URI("https://example.com"),
          payload: { response: nil, body: "", truncated: false },
          request_options: { max_bytes: 1, allowed_content_types: [] },
          redirects_remaining: 1,
        )
      end.to raise_error(WebSearch::Error, "No HTTP response was received.")

      allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(Net::ReadTimeout) # rubocop:disable RSpec/AnyInstance

      expect do
        client.fetch_text("https://example.com/network-timeout", max_bytes: 50, allowed_content_types: ["text/html"])
      end.to raise_error(WebSearch::Error, /Network request failed/)
    end

    it "supports custom headers and can disable range requests" do
      stub_request(:get, "https://example.com/api/search")
        .with(headers: { "X-Test-Token" => "secret-token", "Accept" => "application/json" })
        .to_return(status: 200, body: "{\"ok\":true}", headers: { "Content-Type" => "application/json" })

      client.fetch_text(
        "https://example.com/api/search",
        max_bytes: 200,
        allowed_content_types: ["application/json"],
        headers: { "X-Test-Token" => "secret-token" },
        range_request: false,
      )

      expect(a_request(:get, "https://example.com/api/search")
        .with { |request| request.headers["Range"].blank? }).to have_been_made.once
    end
  end

  describe "private helpers" do
    it "marks reads truncated when chunked bodies exceed the byte cap" do
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

    it "does not set write timeout when the HTTP client does not support it" do
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

    it "falls back to a generic accept header when no content types are provided" do
      expect(client.send(:accept_header_for, [])).to eq("*/*")
    end
  end
end
