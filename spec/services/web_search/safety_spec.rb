# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebSearch::Safety do
  let(:resolver) { class_double(Resolv) }

  describe ".validate_public_url!" do
    it "accepts a normal public https URL" do
      allow(resolver).to receive(:getaddresses).with("example.com").and_return(["93.184.216.34"])

      uri = described_class.validate_public_url!("https://example.com/docs", resolver:)

      expect(uri).to have_attributes(scheme: "https", host: "example.com", path: "/docs")
    end

    it "rejects blank URLs" do
      expect do
        described_class.validate_public_url!("", resolver:)
      end.to raise_error(WebSearch::Safety::Error, "URL is required.")
    end

    it "rejects unsupported schemes" do
      expect do
        described_class.validate_public_url!("ftp://example.com/file", resolver:)
      end.to raise_error(WebSearch::Safety::Error, "Only http and https URLs are allowed.")
    end

    it "rejects embedded credentials" do
      expect do
        described_class.validate_public_url!("https://user:secret@example.com", resolver:)
      end.to raise_error(WebSearch::Safety::Error, "URLs with embedded credentials are not allowed.")
    end

    it "rejects local hostnames" do
      expect do
        described_class.validate_public_url!("https://localhost/admin", resolver:)
      end.to raise_error(WebSearch::Safety::Error, "Local or private hosts are not allowed.")
    end

    it "rejects single-label hosts" do
      allow(resolver).to receive(:getaddresses).with("internal").and_return(["93.184.216.34"])

      expect do
        described_class.validate_public_url!("https://internal/docs", resolver:)
      end.to raise_error(WebSearch::Safety::Error, "A public host name is required.")
    end

    it "rejects unresolved hosts" do
      allow(resolver).to receive(:getaddresses).with("example.com").and_return([])

      expect do
        described_class.validate_public_url!("https://example.com", resolver:)
      end.to raise_error(WebSearch::Safety::Error, "Unable to resolve the requested host.")
    end

    it "rejects private resolved addresses" do
      allow(resolver).to receive(:getaddresses).with("example.com").and_return(["10.0.0.4"])

      expect do
        described_class.validate_public_url!("https://example.com", resolver:)
      end.to raise_error(WebSearch::Safety::Error, "Local or private network targets are not allowed.")
    end

    it "rejects private IP literals" do
      expect do
        described_class.validate_public_url!("http://127.0.0.1/admin", resolver:)
      end.to raise_error(WebSearch::Safety::Error, "Local or private network targets are not allowed.")
    end

    it "rejects private IPv6 literals" do
      expect do
        described_class.validate_public_url!("http://[::1]/admin", resolver:)
      end.to raise_error(WebSearch::Safety::Error, "Local or private network targets are not allowed.")
    end

    it "rejects malformed URLs" do
      expect do
        described_class.validate_public_url!("https://exa mple.com", resolver:)
      end.to raise_error(WebSearch::Safety::Error, "The URL is not valid.")
    end

    it "rejects blank host names through the host validator" do
      safety = described_class.new("https://example.com", resolver:)

      expect do
        safety.send(:validate_host!, "")
      end.to raise_error(WebSearch::Safety::Error, "A public host name is required.")
    end
  end
end
