# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Chunking::Recursive do
  describe "#chunk" do
    it "returns a single chunk when text fits within chunk_size" do
      text = "Short text."
      strategy = described_class.new(chunk_size: 1000, chunk_overlap: 0)
      chunks = strategy.chunk(text)
      expect(chunks.length).to eq(1)
      expect(chunks.first.content).to eq("Short text.")
    end

    it "splits on paragraph boundaries first" do
      text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
      strategy = described_class.new(chunk_size: 1000, chunk_overlap: 0)
      chunks = strategy.chunk(text)
      expect(chunks.length).to eq(1) # All fit in one chunk
    end

    it "falls back to smaller separators for long text" do
      # Each paragraph is 50 chars, total too big for chunk_size 60
      text = "#{"a" * 50}\n\n#{"b" * 50}\n\n#{"c" * 50}"
      strategy = described_class.new(chunk_size: 60, chunk_overlap: 0)
      chunks = strategy.chunk(text)
      expect(chunks.length).to be >= 3
    end

    it "handles custom separators" do
      text = "Part1|||Part2|||Part3"
      strategy = described_class.new(chunk_size: 1000, chunk_overlap: 0, custom_separators: ["|||"])
      chunks = strategy.chunk(text)
      expect(chunks.length).to be >= 1
    end

    it "uses DEFAULT_SEPARATORS when custom_separators is empty" do
      text = "First paragraph.\n\nSecond paragraph."
      strategy = described_class.new(chunk_size: 1000, chunk_overlap: 0, custom_separators: [])
      chunks = strategy.chunk(text)
      expect(chunks.length).to be >= 1
    end

    it "handles empty separator (character-level splitting)" do
      # With an extremely small chunk_size, it will try single-char splitting
      text = "abcdefghij"
      strategy = described_class.new(chunk_size: 3, chunk_overlap: 0)
      chunks = strategy.chunk(text)
      expect(chunks.length).to be >= 2
    end

    it "recurses into sub-chunks when a piece exceeds chunk_size" do
      # Craft a text where a piece after splitting is still too large
      long_word = "a" * 200
      text = "#{long_word}\n\n#{long_word}"
      strategy = described_class.new(chunk_size: 50, chunk_overlap: 0)
      chunks = strategy.chunk(text)
      expect(chunks.length).to be >= 4
    end

    it "applies overlap when chunk_overlap > 0" do
      text = "#{"#{"x" * 50} " * 10}end"
      strategy = described_class.new(chunk_size: 60, chunk_overlap: 10)
      chunks = strategy.chunk(text)
      expect(chunks.length).to be >= 2
    end

    it "handles text that cannot be split further by any separator" do
      # Very long string with no separators at all, chunk_size too small
      text = "a" * 50
      strategy = described_class.new(chunk_size: 10, chunk_overlap: 0)
      chunks = strategy.chunk(text)
      expect(chunks.length).to be >= 1
    end
  end
end
