# frozen_string_literal: true

module Rag
  module Chunking
    class Recursive < Base
      DEFAULT_SEPARATORS = ["\n\n", "\n", ". ", " ", ""].freeze

      protected

      def split(text)
        separators = effective_separators
        recursive_split(text, separators)
      end

      private

      def effective_separators
        custom = options[:custom_separators]
        if custom.is_a?(Array) && custom.any?
          custom.map(&:to_s)
        else
          DEFAULT_SEPARATORS
        end
      end

      def recursive_split(text, separators)
        return [text] if text.length <= chunk_size
        return [text] if separators.empty?

        separator = separators.first
        remaining_separators = separators[1..]
        pieces = split_by_separator(text, separator)

        return recursive_split(text, remaining_separators) if pieces.length <= 1

        merge_pieces(pieces, separator, remaining_separators)
      end

      def split_by_separator(text, separator)
        separator.empty? ? text.chars : text.split(separator)
      end

      def merge_pieces(pieces, separator, remaining_separators)
        results = []
        current = +""

        pieces.each do |piece|
          current, results = process_piece(piece, current, separator, remaining_separators, results)
        end

        results << current unless current.empty?
        results
      end

      def process_piece(piece, current, separator, remaining_seps, results)
        candidate = current.empty? ? piece : "#{current}#{separator}#{piece}"

        if candidate.length <= chunk_size
          [+candidate, results]
        else
          results << current unless current.empty?
          if piece.length > chunk_size
            results.concat(recursive_split(piece, remaining_seps))
            [+"", results]
          else
            [apply_overlap_text(current, piece), results]
          end
        end
      end

      def apply_overlap_text(previous, current)
        return +current if chunk_overlap <= 0 || previous.empty?

        overlap = previous.last(chunk_overlap)
        "#{overlap} #{current}"
      end
    end
  end
end
