# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Steps::ChunkerExecutor do
  let(:chunk_double) { instance_double(Rag::Chunk, content: "text", position: 0, metadata: {}, embedding: nil) }
  let(:chunker_service) do
    instance_double(Rag::Chunking::Base, chunk: [chunk_double])
  end

  before do
    allow(Rag::Chunking::Base).to receive(:for).and_return(chunker_service)
  end

  describe "#call" do
    let(:config) { build(:rag_steps_fixed_size_chunker, chunk_size: 500, chunk_overlap: 100) }
    let(:executor) { described_class.new(config, {}) }

    it "splits each document into chunks using the configured strategy" do
      doc = Rag::Document.new(id: "1", content: "Hello world", metadata: { "src" => "db" })
      allow(Rag::Chunking::Base).to receive(:for).with("fixed_size", anything).and_return(chunker_service)
      allow(chunk_double).to receive_messages(content: "Hello world", position: 0, metadata: {}, embedding: nil)

      result = executor.call([doc])

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first.chunks).not_to be_empty
    end

    it "merges document metadata into chunk metadata" do
      doc = Rag::Document.new(id: "1", content: "Hello", metadata: { "source" => "db" })
      chunk_with_meta = instance_double(Rag::Chunk,
                                        content: "Hello",
                                        position: 0,
                                        metadata: { "chunk_key" => "val" },
                                        embedding: nil,)
      allow(chunker_service).to receive(:chunk).and_return([chunk_with_meta])

      result = executor.call([doc])

      merged_metadata = result.first.chunks.first.metadata
      expect(merged_metadata).to include("source" => "db", "chunk_key" => "val")
    end

    it "returns empty documents array when input is empty" do
      result = executor.call([])
      expect(result).to eq([])
    end

    it "builds chunker with correct strategy and parameters" do
      doc = Rag::Document.new(content: "text")
      executor.call([doc])

      expect(Rag::Chunking::Base).to have_received(:for).with(
        "fixed_size",
        hash_including(chunk_size: 500, chunk_overlap: 100),
      )
    end

    it "passes separator when config responds to separator" do
      config_with_sep = build(:rag_steps_fixed_size_chunker, separator: "\n")
      exec = described_class.new(config_with_sep, {})
      doc = Rag::Document.new(content: "text")
      exec.call([doc])

      expect(Rag::Chunking::Base).to have_received(:for).with(
        "fixed_size",
        hash_including(separator: "\n"),
      )
    end
  end
end
