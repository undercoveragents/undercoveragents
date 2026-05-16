# frozen_string_literal: true

# RubyLLM tool that performs RAG (Retrieval Augmented Generation) queries
# against a vector database using embeddings.
#
# This tool connects to an external SQL database containing chunks and
# documents tables with pgvector embeddings. It embeds the user's query,
# performs a nearest-neighbor search, and returns relevant chunks with
# their associated document metadata.
#
# Each enabled RAG Query tool produces its own RagQueryTool instance so
# that multiple vector stores can be offered to the LLM simultaneously.
#
# Usage:
#   tool_record = Tool.rag_queries.enabled.find(id)
#   tool = RagQueryTool.for_tool(tool_record)
#   chat.with_tool(tool)
#   chat.ask("Find documents about machine learning")
#
class RagQueryTool < RubyLLM::Tool
  include RagToolBehavior

  def self.for_tool(tool_record)
    raise ArgumentError, "Expected a RAG Query tool" unless tool_record.toolable.is_a?(Tools::RagQuery)

    new(tool_record)
  end

  def initialize(tool_record)
    super()
    @tool_record = tool_record
  end

  private

  def tool_name_prefix
    "rag_query"
  end
end
