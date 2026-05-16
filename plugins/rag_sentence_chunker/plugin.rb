# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("sentence_chunker") do
  name "Sentence Chunker"
  version "1.0.0"
  author "Undercover Agents"
  description "Split documents at sentence boundaries. Groups sentences into chunks of configurable size."
  icon "fa-solid fa-align-left"
  category [:rag_chunking]
  add_rag_chunker "SentenceChunker"
end
