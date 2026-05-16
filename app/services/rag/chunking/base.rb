# frozen_string_literal: true

module Rag
  module Chunking
    class Base
      attr_reader :chunk_size, :chunk_overlap, :options

      def self.for(strategy, chunk_size:, chunk_overlap: 0, **)
        strategy_name = strategy.to_s.camelize
        klass = "Rag::Chunking::#{strategy_name}".constantize
        klass.new(chunk_size:, chunk_overlap:, **)
      rescue NameError
        raise ArgumentError, "Unknown chunking strategy: #{strategy}"
      end

      def initialize(chunk_size:, chunk_overlap: 0, **options)
        @chunk_size = chunk_size
        @chunk_overlap = chunk_overlap
        @options = options
      end

      def chunk(text)
        return [] if text.nil? || text.strip.empty?

        pieces = split(text)
        chunks = pieces.each_with_index.map do |content, index|
          Rag::Chunk.new(content: content.strip, position: index)
        end
        chunks.reject { |c| c.content.empty? }
      end

      protected

      def split(_text)
        raise NotImplementedError
      end

      def merge_pieces(pieces)
        return pieces if pieces.empty?

        merged = []
        current = +""

        pieces.each do |piece|
          piece = piece.strip
          next if piece.empty?

          if current.empty?
            current = +piece
          elsif (current.length + piece.length + 1) <= chunk_size
            current << "\n" << piece
          else
            merged << current
            current = apply_overlap(current, piece)
          end
        end

        merged << current unless current.empty?
        merged
      end

      private

      def apply_overlap(previous, current)
        return +current if chunk_overlap <= 0

        overlap_text = previous.last(chunk_overlap)
        "#{overlap_text}\n#{current}"
      end
    end
  end
end
