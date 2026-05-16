# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("sql_database") do
  name "SQL Database"
  version "1.0.0"
  author "Undercover Agents"
  description "Connect to relational databases, query with natural language, " \
              "and use PostgreSQL for RAG document ingestion and storage."
  icon "fa-solid fa-database"
  category [:connector, :tool, :rag_input, :rag_storage]
  add_connector "SqlDatabase"
  add_tool "SqlQuery"
  add_rag_input "SqlDatabaseSource"
  add_rag_storage "SqlDatabaseStorage"
end
