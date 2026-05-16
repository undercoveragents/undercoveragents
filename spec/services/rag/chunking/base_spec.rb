# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Chunking::Base do
  describe ".for" do
    it "creates a FixedSize strategy" do
      strategy = described_class.for("fixed_size", chunk_size: 100)
      expect(strategy).to be_a(Rag::Chunking::FixedSize)
    end

    it "creates a Recursive strategy" do
      strategy = described_class.for("recursive", chunk_size: 100)
      expect(strategy).to be_a(Rag::Chunking::Recursive)
    end

    it "creates a Paragraph strategy" do
      strategy = described_class.for("paragraph", chunk_size: 100)
      expect(strategy).to be_a(Rag::Chunking::Paragraph)
    end

    it "creates a Sentence strategy" do
      strategy = described_class.for("sentence", chunk_size: 100)
      expect(strategy).to be_a(Rag::Chunking::Sentence)
    end

    it "creates a MarkdownHeader strategy" do
      strategy = described_class.for("markdown_header", chunk_size: 100)
      expect(strategy).to be_a(Rag::Chunking::MarkdownHeader)
    end

    it "raises for unknown strategy" do
      expect { described_class.for("unknown", chunk_size: 100) }.to raise_error(ArgumentError, /Unknown/)
    end
  end

  describe "#chunk" do
    it "returns empty array for nil text" do
      strategy = described_class.for("fixed_size", chunk_size: 100)
      expect(strategy.chunk(nil)).to eq([])
    end

    it "returns empty array for blank text" do
      strategy = described_class.for("fixed_size", chunk_size: 100)
      expect(strategy.chunk("   ")).to eq([])
    end

    it "returns Rag::Chunk objects" do
      strategy = described_class.for("fixed_size", chunk_size: 100)
      chunks = strategy.chunk("Hello world")
      expect(chunks.first).to be_a(Rag::Chunk)
      expect(chunks.first.content).to eq("Hello world")
      expect(chunks.first.position).to eq(0)
    end
  end

  describe "#chunk with merge_pieces" do
    it "handles text where the split returns empty pieces array" do
      strategy = described_class.for("fixed_size", chunk_size: 100)
      allow(strategy).to receive(:split).and_return([])
      expect(strategy.chunk("some text")).to eq([])
    end

    it "merges short paragraphs together" do
      strategy = described_class.for("paragraph", chunk_size: 200, chunk_overlap: 0)
      text = "Short one.\n\nShort two.\n\nShort three."
      chunks = strategy.chunk(text)
      expect(chunks).not_to be_empty
      # Short paragraphs should be merged into larger chunks
      expect(chunks.first.content).to be_present
    end

    it "applies overlap between chunks when chunk_overlap > 0" do
      # Use a paragraph strategy with very small chunk size to force splits and overlap
      strategy = described_class.for("paragraph", chunk_size: 20, chunk_overlap: 5)
      text = "#{"A" * 18}\n\n" * 4
      chunks = strategy.chunk(text)
      expect(chunks.length).to be >= 2
    end
  end

  describe "#merge_pieces (protected, via send)" do
    let(:strategy) { described_class.for("paragraph", chunk_size: 200, chunk_overlap: 0) }

    it "returns empty array immediately when pieces is empty" do
      result = strategy.send(:merge_pieces, [])
      expect(result).to eq([])
    end

    it "skips whitespace-only pieces and returns empty array when all are blank" do
      result = strategy.send(:merge_pieces, ["  ", "\t", " "])
      expect(result).to eq([])
    end
  end

  describe "#split (abstract method)" do
    it "raises NotImplementedError when called directly on a Base instance" do
      base = described_class.new(chunk_size: 100)
      expect { base.chunk("some text") }.to raise_error(NotImplementedError)
    end
  end
end
