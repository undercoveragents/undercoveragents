# frozen_string_literal: true

module RagSteps
  # Splits documents into fixed-size chunks by character count.
  # Configuration is stored as JSONB on the RagStep model.
  class FixedSizeChunker
    include UndercoverAgents::PluginSystem::Configurator
    include RagStepPlugin
    include RagSteps::ChunkerConfigurable

    attribute :separator, :string

    # ── Step Type Protocol ────────────────────────────────────────

    key "fixed_size_chunker"
    label "Fixed Size"
    icon "fa-solid fa-ruler"
    stage :chunking
    description [
      "Split documents into fixed-size chunks with configurable overlap.",
      "Simple and predictable chunking strategy.",
    ].join(" ")

    def self.permitted_params(params)
      params.expect(fixed_size_chunker: [:chunk_size, :chunk_overlap, :separator])
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    # ── Execution ─────────────────────────────────────────────────

    def chunking_strategy = "fixed_size"

    def summary
      "Fixed Size — #{chunk_size} chars, #{chunk_overlap} overlap"
    end
  end
end
