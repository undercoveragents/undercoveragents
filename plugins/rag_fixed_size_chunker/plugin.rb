# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("fixed_size_chunker") do
  name "Fixed Size Chunker"
  version "1.0.0"
  author "Undercover Agents"
  description "Split documents into fixed-size chunks with configurable overlap. " \
              "Simple and predictable chunking strategy."
  icon "fa-solid fa-ruler"
  category [:rag_chunking]
  add_rag_chunker "FixedSizeChunker"
end
