# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Chunking::MarkdownHeader do
  describe "#chunk" do
    it "splits text by markdown headings" do
      text = "# Title\n\nIntro text.\n\n## Section 1\n\nContent 1.\n\n## Section 2\n\nContent 2."
      chunker = described_class.new(chunk_size: 1000, chunk_overlap: 0)
      result = chunker.chunk(text)

      expect(result).to be_an(Array)
      expect(result.length).to be >= 2
    end

    it "prefixes chunks with header context" do
      text = "# Main\n\n## Sub\n\nSome text here."
      chunker = described_class.new(chunk_size: 1000, chunk_overlap: 0)
      result = chunker.chunk(text)

      sub_chunk = result.find { |c| c.content.include?("Some text here") }
      expect(sub_chunk.content).to include("Main > Sub")
    end

    it "sub-splits large sections into smaller chunks" do
      paragraphs = Array.new(5) { "x" * 40 }.join("\n\n")
      text = "# Title\n\n#{paragraphs}"
      chunker = described_class.new(chunk_size: 50, chunk_overlap: 0)
      result = chunker.chunk(text)

      expect(result.length).to be >= 2
    end

    it "returns empty for blank text" do
      chunker = described_class.new(chunk_size: 100, chunk_overlap: 0)
      expect(chunker.chunk("")).to be_empty
    end

    it "handles text with no headings" do
      chunker = described_class.new(chunk_size: 1000, chunk_overlap: 0)
      result = chunker.chunk("Just plain text here.")
      expect(result.length).to eq(1)
      expect(result.first.content).to eq("Just plain text here.")
    end
  end
end
