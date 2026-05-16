# frozen_string_literal: true

module Rag
  module Chunking
    class FixedSize < Base
      protected

      def split(text)
        sep = options[:separator]

        if sep.present?
          pieces = text.split(sep)
          merge_pieces(pieces)
        else
          split_by_size(text)
        end
      end

      private

      def split_by_size(text)
        chunks = []
        start_pos = 0

        while start_pos < text.length
          end_pos = [start_pos + chunk_size, text.length].min
          chunks << text[start_pos...end_pos]
          start_pos += (chunk_size - chunk_overlap)
        end

        chunks
      end
    end
  end
end
