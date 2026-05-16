# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Steps::ChunkerExecutor do
  let(:config) { build(:rag_steps_paragraph_chunker) }

  describe "#call" do
    it "chunks documents using the configured strategy" do
      doc = Rag::Document.new(
        id: "1",
        content: "First paragraph.\n\nSecond paragraph.",
        metadata: { source: "test" },
        chunks: [],
      )

      result = described_class.new(config).call([doc])

      expect(result.length).to eq(1)
      expect(result.first.chunks).not_to be_empty
      expect(result.first.chunks.first.content).to be_present
    end

    it "enriches chunks with document metadata" do
      doc = Rag::Document.new(
        id: "1",
        content: "Some content here.",
        metadata: { source: "test_file" },
        chunks: [],
      )

      result = described_class.new(config).call([doc])

      expect(result.first.chunks.first.metadata).to include(source: "test_file")
    end

    it "handles blank content gracefully" do
      doc = Rag::Document.new(id: "1", content: "", metadata: {}, chunks: [])
      result = described_class.new(config).call([doc])
      expect(result.first.chunks).to be_empty
    end
  end
end
