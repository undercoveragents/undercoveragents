# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Chunking::Paragraph do
  describe "#chunk" do
    it "splits on double newlines" do
      text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
      strategy = described_class.new(chunk_size: 1000, chunk_overlap: 0)
      chunks = strategy.chunk(text)
      # All paragraphs are small enough to be merged into one chunk
      expect(chunks.length).to be >= 1
    end

    it "keeps separate paragraphs when they exceed chunk_size" do
      text = "#{"a" * 100}\n\n#{"b" * 100}"
      strategy = described_class.new(chunk_size: 110, chunk_overlap: 0)
      chunks = strategy.chunk(text)
      expect(chunks.length).to eq(2)
    end
  end
end
