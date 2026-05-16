# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Chunking::FixedSize do
  describe "#chunk with separator" do
    it "splits text on non-blank separator and merges into chunks" do
      chunker = described_class.new(chunk_size: 20, chunk_overlap: 0, separator: ",")
      result = chunker.chunk("Hello,world,this,is,a,test,of,splitting")
      expect(result).to be_an(Array)
      expect(result).to all(be_a(Rag::Chunk))
      result.each { |c| expect(c.content.length).to be <= 20 }
    end

    it "returns empty for blank text" do
      chunker = described_class.new(chunk_size: 100, chunk_overlap: 0, separator: ",")
      expect(chunker.chunk("")).to be_empty
    end
  end

  describe "#chunk without separator (split_by_size)" do
    it "splits text into fixed-size windows" do
      chunker = described_class.new(chunk_size: 10, chunk_overlap: 0)
      result = chunker.chunk("abcdefghijklmnopqrstuvwxyz")
      expect(result.length).to eq(3)
      expect(result[0].content).to eq("abcdefghij")
      expect(result[1].content).to eq("klmnopqrst")
      expect(result[2].content).to eq("uvwxyz")
    end

    it "applies overlap between chunks" do
      chunker = described_class.new(chunk_size: 10, chunk_overlap: 3)
      result = chunker.chunk("abcdefghijklmnopqrst")
      expect(result.length).to be >= 2
      # Second chunk should start at position (10 - 3) = 7
      expect(result[1].content).to start_with("h")
    end
  end
end
