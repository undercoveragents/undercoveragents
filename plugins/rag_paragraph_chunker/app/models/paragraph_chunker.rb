# frozen_string_literal: true

module RagSteps
  # Splits documents into chunks by paragraph boundaries (double newlines).
  class ParagraphChunker
    include UndercoverAgents::PluginSystem::Configurator
    include RagStepPlugin
    include RagSteps::ChunkerConfigurable

    attribute :min_paragraph_size, :integer, default: 100

    # ── Step Type Protocol ────────────────────────────────────────

    key "paragraph_chunker"
    label "Paragraph"
    icon "fa-solid fa-paragraph"
    stage :chunking
    description "Split documents by paragraph boundaries. Merges small paragraphs to meet minimum chunk size."

    def self.permitted_params(params)
      params.expect(paragraph_chunker: [:chunk_size, :chunk_overlap, :min_paragraph_size])
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    # ── Execution ─────────────────────────────────────────────────

    def chunking_strategy = "paragraph"

    def summary
      "Paragraph — #{chunk_size} chars, #{chunk_overlap} overlap"
    end
  end
end
