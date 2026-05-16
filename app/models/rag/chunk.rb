# frozen_string_literal: true

module Rag
  # Represents a single chunk of content within a document.
  # Runtime-only (not persisted) — serves as the contract between steps.
  Chunk = Data.define(:content, :position, :metadata, :embedding) do
    def initialize(content:, position: 0, metadata: {}, embedding: nil)
      super
    end

    def with_embedding(new_embedding)
      with(embedding: new_embedding)
    end

    def to_h
      { content:, position:, metadata:, embedding: }
    end
  end
end
