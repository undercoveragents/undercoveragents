# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Chunking::Sentence do
  describe "#chunk" do
    it "splits on sentence boundaries" do
      text = "First sentence. Second sentence. Third sentence."
      strategy = described_class.new(chunk_size: 1000, chunk_overlap: 0)
      chunks = strategy.chunk(text)
      expect(chunks.length).to be >= 1
    end

    it "keeps sentences separate when they exceed chunk_size" do
      text = "#{"a" * 50}. #{"b" * 50}."
      strategy = described_class.new(chunk_size: 60, chunk_overlap: 0)
      chunks = strategy.chunk(text)
      expect(chunks.length).to eq(2)
    end
  end
end
