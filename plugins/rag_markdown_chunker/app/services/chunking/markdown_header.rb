# frozen_string_literal: true

module Rag
  module Chunking
    class MarkdownHeader < Base
      HEADER_REGEX = /^(\#{1,6})\s+(.+)$/

      protected

      def split(text)
        sections = extract_sections(text)
        sections.flat_map { |section| build_section_chunks(section) }
      end

      private

      def build_section_chunks(section)
        content = section[:content].strip
        return [] if content.empty?

        header_context = section[:headers].pluck(:text).join(" > ")
        raw_chunks = content.length <= chunk_size ? [content] : sub_split(content)
        raw_chunks.map { |chunk| prefix_with_headers(header_context, chunk) }
      end

      def sub_split(content)
        paragraphs = content.split(/\n\s*\n/)
        merge_pieces(paragraphs)
      end

      def prefix_with_headers(header_context, content)
        header_context.present? ? "#{header_context}\n\n#{content}" : content
      end

      def extract_sections(text)
        sections = []
        current_headers = []
        current_content = +""

        text.each_line do |line|
          match = line.match(HEADER_REGEX)
          if match
            unless current_content.strip.empty? && sections.empty? && current_headers.empty?
              sections << { headers: current_headers.dup, content: current_content }
            end

            level = match[1].length
            header_text = match[2].strip

            current_headers = current_headers.select { |h| h[:level] < level }
            current_headers << { level:, text: header_text }
            current_content = +""
          else
            current_content << line
          end
        end

        sections << { headers: current_headers.dup, content: current_content }
        sections
      end
    end
  end
end
