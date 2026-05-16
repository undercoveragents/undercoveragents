# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("tool_rag_query") do
  name "RAG Query Tool"
  version "1.0.0"
  author "Undercover Agents"
  description "Perform pgvector similarity search against RAG embeddings. " \
              "Configurable tables, embedding model, distance method, and thresholds."
  icon "fa-solid fa-magnifying-glass"
  category [:tool]
  add_tool "RagQuery"
end
