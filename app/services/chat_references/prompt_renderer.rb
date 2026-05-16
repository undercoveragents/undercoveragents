# frozen_string_literal: true

module ChatReferences
  class PromptRenderer
    def initialize(content:, references:)
      @content = content.to_s
      @references = Array(references)
    end

    def render
      references_with_mentions.reduce(content) do |text, reference|
        prompt_identifier = ReferenceFormatter.prompt_identifier(reference)
        next text unless prompt_identifier

        text.gsub(reference.fetch("mention"), prompt_identifier)
      end
    end

    private

    attr_reader :content, :references

    def references_with_mentions
      references
        .select { |reference| reference["mention"].present? }
        .sort_by { |reference| -reference.fetch("mention").length }
    end
  end
end
