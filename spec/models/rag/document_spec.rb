# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Document do
  let(:chunk) { Rag::Chunk.new(content: "part 1", position: 0) }

  describe ".new" do
    it "creates with defaults" do
      doc = described_class.new

      expect(doc.id).to be_nil
      expect(doc.content).to eq("")
      expect(doc.metadata).to eq({})
      expect(doc.chunks).to eq([])
    end

    it "creates with all attributes" do
      doc = described_class.new(id: "abc", content: "hello", metadata: { "src" => "db" }, chunks: [chunk])

      expect(doc.id).to eq("abc")
      expect(doc.content).to eq("hello")
      expect(doc.metadata).to eq({ "src" => "db" })
      expect(doc.chunks).to contain_exactly(chunk)
    end
  end

  describe "#with_chunks" do
    it "returns a new document with updated chunks" do
      doc = described_class.new(id: "1", content: "text")
      updated = doc.with_chunks([chunk])

      expect(updated.chunks).to contain_exactly(chunk)
      expect(updated.id).to eq("1")
      expect(doc.chunks).to eq([])
    end
  end

  describe "#content_hash" do
    it "returns a SHA256 hex digest of the content" do
      doc = described_class.new(content: "hello world")
      expect(doc.content_hash).to eq(Digest::SHA256.hexdigest("hello world"))
    end

    it "returns a consistent hash for the same content" do
      doc1 = described_class.new(content: "same")
      doc2 = described_class.new(content: "same")
      expect(doc1.content_hash).to eq(doc2.content_hash)
    end

    it "returns different hashes for different content" do
      doc1 = described_class.new(content: "one")
      doc2 = described_class.new(content: "two")
      expect(doc1.content_hash).not_to eq(doc2.content_hash)
    end
  end

  describe "#to_h" do
    it "serializes the document including chunks" do
      doc = described_class.new(id: "1", content: "hello", metadata: { "k" => "v" }, chunks: [chunk])

      result = doc.to_h

      expect(result[:id]).to eq("1")
      expect(result[:content]).to eq("hello")
      expect(result[:metadata]).to eq({ "k" => "v" })
      expect(result[:chunks]).to be_an(Array)
      expect(result[:chunks].first[:content]).to eq("part 1")
    end
  end
end
