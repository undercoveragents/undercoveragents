# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("markdown_chunker") do
  name "Markdown Chunker"
  version "1.0.0"
  author "Undercover Agents"
  description "Split documents by Markdown headings. Preserves header hierarchy in chunk metadata."
  icon "fa-brands fa-markdown"
  category [:rag_chunking]
  add_rag_chunker "MarkdownChunker"
end
