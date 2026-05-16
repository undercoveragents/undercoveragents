# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("paragraph_chunker") do
  name "Paragraph Chunker"
  version "1.0.0"
  author "Undercover Agents"
  description "Split documents by paragraph boundaries. Merges small paragraphs to meet minimum chunk size."
  icon "fa-solid fa-paragraph"
  category [:rag_chunking]
  add_rag_chunker "ParagraphChunker"
end
