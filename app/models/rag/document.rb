# frozen_string_literal: true

# Immutable data structures flowing through RAG steps.
# These are runtime-only (not persisted) and serve as the contract between steps.
module Rag
  # Represents a document flowing through the pipeline.
  # Source steps produce documents; transformer steps modify them;
  # destination steps persist them.
  Document = Data.define(:id, :content, :metadata, :chunks) do
    def initialize(id: nil, content: "", metadata: {}, chunks: [])
      super
    end

    def content_hash
      Digest::SHA256.hexdigest(content.to_s)
    end

    def with_chunks(new_chunks)
      with(chunks: new_chunks)
    end

    def to_h
      { id:, content:, metadata:, chunks: chunks.map(&:to_h) }
    end
  end
end
