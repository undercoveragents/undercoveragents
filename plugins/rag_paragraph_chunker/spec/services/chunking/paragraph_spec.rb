# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Chunking::Paragraph do
  describe "#chunk" do
    it "splits text by paragraph breaks" do
      text = "First paragraph here.\n\nSecond paragraph here.\n\nThird paragraph here."
      chunker = described_class.new(chunk_size: 1000, chunk_overlap: 0)
      result = chunker.chunk(text)

      expect(result).to be_an(Array)
      expect(result.length).to eq(1) # All fit in one chunk
      expect(result.first.content).to include("First paragraph")
    end

    it "merges small paragraphs into single chunks" do
      text = "Short.\n\nAlso short.\n\nStill short."
      chunker = described_class.new(chunk_size: 1000, chunk_overlap: 0)
      result = chunker.chunk(text)

      expect(result.length).to eq(1)
    end

    it "splits large paragraphs into multiple chunks" do
      text = "#{"A" * 200}\n\n" * 5
      chunker = described_class.new(chunk_size: 250, chunk_overlap: 0)
      result = chunker.chunk(text)

      expect(result.length).to be > 1
    end

    it "returns empty for blank text" do
      chunker = described_class.new(chunk_size: 100, chunk_overlap: 0)
      expect(chunker.chunk("")).to be_empty
    end

    it "returns empty for nil text" do
      chunker = described_class.new(chunk_size: 100, chunk_overlap: 0)
      expect(chunker.chunk(nil)).to be_empty
    end

    it "assigns sequential positions to chunks" do
      text = "#{"Paragraph content here. " * 20}\n\n" * 5
      chunker = described_class.new(chunk_size: 100, chunk_overlap: 0)
      result = chunker.chunk(text)

      positions = result.map(&:position)
      expect(positions).to eq(positions.sort)
    end
  end
end
