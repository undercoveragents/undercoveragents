# frozen_string_literal: true

module Rag
  module Chunking
    class Paragraph < Base
      protected

      def split(text)
        paragraphs = text.split(/\n\s*\n/)
        merge_pieces(paragraphs)
      end
    end
  end
end
