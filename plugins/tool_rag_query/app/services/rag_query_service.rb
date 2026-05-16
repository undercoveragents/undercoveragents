# frozen_string_literal: true

module Tools
  # Legacy service for RAG queries. Delegates to the generic RagSearchService.
  #
  # Maintained for backward compatibility with existing callers that pass
  # sql_database as a separate argument.
  #
  # Prefer using Tools::RagSearchService directly for new code.
  #
  class RagQueryService < RagSearchService
    # @param sql_database [Connectors::SqlDatabase] (ignored — derived from rag_query)
    # @param rag_query [Tools::RagQuery] the RAG query configuration
    # @param llm_context [Object, nil] optional LLM provider context
    def initialize(_sql_database = nil, rag_query:, llm_context: nil)
      super(rag_query, llm_context:)
    end
  end
end
