# frozen_string_literal: true

module Rag
  module Chunking
    class Sentence < Base
      SENTENCE_BOUNDARY = /(?<=[.!?])\s+/

      protected

      def split(text)
        sentences = text.split(SENTENCE_BOUNDARY)
        merge_pieces(sentences)
      end
    end
  end
end
