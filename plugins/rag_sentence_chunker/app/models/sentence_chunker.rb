# frozen_string_literal: true

module RagSteps
  # Splits documents into chunks by sentence boundaries.
  class SentenceChunker
    include UndercoverAgents::PluginSystem::Configurator
    include RagStepPlugin
    include RagSteps::ChunkerConfigurable

    # ── Step Type Protocol ────────────────────────────────────────

    key "sentence_chunker"
    label "Sentences"
    icon "fa-solid fa-align-left"
    stage :chunking
    description "Split documents at sentence boundaries. Groups sentences into chunks of configurable size."

    def self.permitted_params(params)
      params.expect(sentence_chunker: [:chunk_size, :chunk_overlap])
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    # ── Execution ─────────────────────────────────────────────────

    def chunking_strategy = "sentence"

    def summary
      "Sentences — #{chunk_size} chars, #{chunk_overlap} overlap"
    end
  end
end
