# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Steps::ChunkerExecutor do
  let(:config) { build(:rag_steps_sentence_chunker) }

  describe "#call" do
    it "chunks documents using the configured strategy" do
      doc = Rag::Document.new(
        id: "1",
        content: "First sentence. Second sentence. Third sentence.",
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
        content: "Some content here.",
        metadata: { source: "test_file" },
        chunks: [],
      )

      result = described_class.new(config).call([doc])

      expect(result.first.chunks.first.metadata).to include(source: "test_file")
    end
  end
end
