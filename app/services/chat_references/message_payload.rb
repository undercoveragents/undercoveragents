# frozen_string_literal: true

require "base64"

module ChatReferences
  class MessagePayload
    MARKER_PATTERN = %r{(?:\n\n)?<!-- chat_references:([A-Za-z0-9+/=]+) -->\s*\z}

    def self.pack(content:, references:)
      new(content:, references:).packed_content
    end

    def self.parse(content)
      raw_content = content.to_s
      match = raw_content.match(MARKER_PATTERN)
      return new(content: raw_content, references: []) unless match

      new(
        content: raw_content.sub(MARKER_PATTERN, ""),
        references: decode_references(match[1]),
      )
    end

    def self.decode_references(encoded)
      JSON.parse(Base64.strict_decode64(encoded)).grep(Hash)
    rescue ArgumentError, JSON::ParserError
      []
    end

    def initialize(content:, references:)
      @content = content.to_s
      @references = Array(references).grep(Hash).map(&:deep_stringify_keys)
    end

    attr_reader :content, :references

    def packed_content
      return content if references.empty?

      "#{content}\n\n<!-- chat_references:#{encoded_references} -->"
    end

    def prompt_content
      rendered_content = PromptRenderer.new(content:, references:).render
      reference_prompts = reference_prompt_lines
      return rendered_content if reference_prompts.empty?

      [rendered_content.presence, "Referenced records:", *reference_prompts.map { |prompt| "- #{prompt}" }]
        .compact
        .join("\n")
    end

    def display_content = content

    def references? = references.any?

    private

    def encoded_references
      Base64.strict_encode64(JSON.generate(references))
    end

    def reference_prompt_lines
      references.filter_map do |reference|
        prompt_summary = reference_prompt_summary(reference)
        next unless prompt_summary

        label = reference_prompt_label(reference)
        label ? "#{label} => #{prompt_summary}" : prompt_summary
      end.uniq
    end

    def reference_prompt_summary(reference)
      prompt_identifier = ReferenceFormatter.prompt_identifier(reference)
      return unless prompt_identifier

      return prompt_identifier unless enriched_reference_summary?(reference)

      summary = enriched_reference_details(reference) || prompt_identifier
      type = reference["type"].presence

      type ? "#{type}: #{summary}" : summary
    end

    def enriched_reference_summary?(reference)
      reference["type"].present? || reference["label"].present? || reference["slug"].present?
    end

    def enriched_reference_details(reference)
      [
        reference["label"].presence,
        reference_id_detail(reference),
        reference_slug_detail(reference),
      ].compact.join(" | ").presence
    end

    def reference_id_detail(reference)
      "id: #{reference["id"]}" if reference["id"].present?
    end

    def reference_slug_detail(reference)
      slug = reference["slug"].presence
      "slug: #{slug}" if slug
    end

    def reference_prompt_label(reference)
      mention = reference["mention"].presence
      return mention if mention && content.include?(mention)

      reference["display_mention"].presence || reference["label"].presence
    end
  end
end
