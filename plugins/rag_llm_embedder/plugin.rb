# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("llm_embedder") do
  name "LLM Embedder"
  version "1.0.0"
  author "Undercover Agents"
  description "Generate embeddings using an LLM provider. Supports token-aware batching for efficient processing."
  icon "fa-solid fa-vector-square"
  category [:rag_embedding]
  add_rag_embedding "LlmEmbedder"
end
