# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Chunking::Recursive do
  it "returns the full text when recursive splitting runs out of separators" do
    chunker = described_class.new(chunk_size: 5, chunk_overlap: 0)

    expect(chunker.send(:recursive_split, "abcdefgh", [])).to eq(["abcdefgh"])
  end

  it "returns text as single chunk when shorter than chunk_size" do
    chunker = described_class.new(chunk_size: 100, chunk_overlap: 0)
    result = chunker.chunk("Short text")
    expect(result.length).to eq(1)
    expect(result[0].content).to eq("Short text")
  end

  it "splits long text into multiple chunks" do
    chunker = described_class.new(chunk_size: 20, chunk_overlap: 0)
    text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
    result = chunker.chunk(text)
    expect(result.length).to be >= 2
    result.each { |c| expect(c.content.length).to be <= 20 }
  end
end
