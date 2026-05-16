# frozen_string_literal: true

module RagSteps
  # Splits documents into chunks by Markdown heading levels.
  class MarkdownChunker
    include UndercoverAgents::PluginSystem::Configurator
    include RagStepPlugin
    include RagSteps::ChunkerConfigurable

    # ── Step Type Protocol ────────────────────────────────────────

    key "markdown_chunker"
    label "Markdown"
    icon "fa-brands fa-markdown"
    stage :chunking
    description "Split documents by Markdown headings. Preserves header hierarchy in chunk metadata."

    def self.permitted_params(params)
      params.expect(markdown_chunker: [:chunk_size, :chunk_overlap])
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    # ── Execution ─────────────────────────────────────────────────

    def chunking_strategy = "markdown_header"

    def summary
      "Markdown — #{chunk_size} chars, #{chunk_overlap} overlap"
    end
  end
end
