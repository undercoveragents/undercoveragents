# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Chunking::FixedSize do
  let(:text) { "a" * 250 }

  describe "#chunk" do
    it "splits text into fixed-size chunks" do
      strategy = described_class.new(chunk_size: 100, chunk_overlap: 0)
      chunks = strategy.chunk(text)
      expect(chunks.length).to eq(3)
      expect(chunks[0].content.length).to eq(100)
      expect(chunks[1].content.length).to eq(100)
      expect(chunks[2].content.length).to eq(50)
    end

    it "applies overlap between chunks" do
      text = "a" * 200
      strategy = described_class.new(chunk_size: 100, chunk_overlap: 20)
      chunks = strategy.chunk(text)
      # With overlap, we get more chunks
      expect(chunks.length).to be >= 2
    end

    it "handles text shorter than chunk_size" do
      strategy = described_class.new(chunk_size: 1000, chunk_overlap: 0)
      chunks = strategy.chunk("Short text")
      expect(chunks.length).to eq(1)
      expect(chunks[0].content).to eq("Short text")
    end
  end
end
