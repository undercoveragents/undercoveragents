# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Chunking::MarkdownHeader do
  describe "#chunk" do
    it "splits on markdown headers" do
      text = "# Title\n\nIntroduction text here.\n\n## Section 1\n\n" \
             "First section content.\n\n## Section 2\n\nSecond section content."
      strategy = described_class.new(chunk_size: 1000, chunk_overlap: 0)
      chunks = strategy.chunk(text)
      expect(chunks.length).to be >= 1
      expect(chunks.first.content).to include("Title")
    end

    it "preserves header hierarchy in content" do
      text = "# Main\n\nText under main.\n\n## Sub\n\nText under sub."
      strategy = described_class.new(chunk_size: 50, chunk_overlap: 0)
      chunks = strategy.chunk(text)
      expect(chunks.length).to be >= 2
    end
  end
end
