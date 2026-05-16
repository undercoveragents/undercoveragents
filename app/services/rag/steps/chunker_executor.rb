# frozen_string_literal: true

module Rag
  module Steps
    class ChunkerExecutor
      def initialize(step_config, context = {})
        @config = step_config
        @context = context
      end

      def call(documents)
        chunker = build_chunker

        documents.map do |doc|
          chunks = chunker.chunk(doc.content)

          enriched_chunks = chunks.map do |chunk|
            Rag::Chunk.new(
              content: chunk.content,
              position: chunk.position,
              metadata: doc.metadata.merge(chunk.metadata),
              embedding: chunk.embedding,
            )
          end

          doc.with_chunks(enriched_chunks)
        end
      end

      private

      def build_chunker
        Rag::Chunking::Base.for(
          @config.chunking_strategy,
          chunk_size: @config.chunk_size,
          chunk_overlap: @config.chunk_overlap,
          separator: @config.respond_to?(:separator) ? @config.separator : nil,
        )
      end
    end
  end
end
