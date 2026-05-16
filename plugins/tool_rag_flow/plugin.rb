# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("tool_rag_flow") do
  name "RAG Flow Tool"
  version "1.0.0"
  author "Undercover Agents"
  description "Expose RagFlow vector search as an agent tool."
  icon "fa-solid fa-diagram-project"
  category [:tool]
  add_tool "RagFlow"
end
