# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Chunking::Sentence do
  describe "#chunk" do
    it "splits text by sentence boundaries" do
      text = "First sentence. Second sentence! Third sentence?"
      chunker = described_class.new(chunk_size: 1000, chunk_overlap: 0)
      result = chunker.chunk(text)

      expect(result).to be_an(Array)
      expect(result.first.content).to include("First sentence")
    end

    it "merges short sentences into single chunks" do
      text = "Short. Also short. Still short."
      chunker = described_class.new(chunk_size: 1000, chunk_overlap: 0)
      result = chunker.chunk(text)

      expect(result.length).to eq(1)
    end

    it "splits long text into multiple chunks" do
      text = ("This is a sentence. " * 50).strip
      chunker = described_class.new(chunk_size: 100, chunk_overlap: 0)
      result = chunker.chunk(text)

      expect(result.length).to be > 1
    end

    it "returns empty for blank text" do
      chunker = described_class.new(chunk_size: 100, chunk_overlap: 0)
      expect(chunker.chunk("")).to be_empty
    end

    it "assigns sequential positions to chunks" do
      text = ("Hello world. " * 30).strip
      chunker = described_class.new(chunk_size: 50, chunk_overlap: 0)
      result = chunker.chunk(text)

      positions = result.map(&:position)
      expect(positions).to eq(positions.sort)
    end
  end
end
