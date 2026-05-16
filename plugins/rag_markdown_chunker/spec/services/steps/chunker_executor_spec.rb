# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Steps::ChunkerExecutor do
  let(:config) { build(:rag_steps_markdown_chunker) }

  describe "#call" do
    it "chunks documents using markdown heading strategy" do
      doc = Rag::Document.new(
        id: "1",
        content: "# Title\n\nSome content here.\n\n## Section\n\nMore content.",
        metadata: { source: "test" },
        chunks: [],
      )

      result = described_class.new(config).call([doc])

      expect(result.length).to eq(1)
      expect(result.first.chunks).not_to be_empty
    end

    it "enriches chunks with document metadata" do
      doc = Rag::Document.new(
        id: "1",
        content: "# Heading\n\nBody text.",
        metadata: { source: "test_file" },
        chunks: [],
      )

      result = described_class.new(config).call([doc])

      expect(result.first.chunks.first.metadata).to include(source: "test_file")
    end
  end
end
