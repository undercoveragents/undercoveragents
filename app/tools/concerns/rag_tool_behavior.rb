# frozen_string_literal: true

# Shared behavior for RAG-based RubyLLM::Tool subclasses.
#
# Provides common parameter definitions, name sanitization, description,
# execution flow, error handling, and result formatting shared between
# RagQueryTool and RagFlowTool.
#
# Including classes must:
#   - call `super()` then set `@tool_record` in `initialize`
#   - implement `tool_name_prefix` (e.g. "rag_query", "rag_flow")
#
module RagToolBehavior
  extend ActiveSupport::Concern

  included do
    param :query, desc: "The natural language query to search the knowledge base with"
    param :limit, type: :integer,
                  desc: "Maximum number of chunks to return. Overrides the default limit.",
                  required: false
  end

  def name
    sanitize_tool_name(tool_name_prefix)
  end

  def description
    toolable.effective_instructions
  end

  def execute(query:, limit: nil)
    effective_limit = limit || toolable.results_limit
    llm_context = resolve_llm_context

    service = Tools::RagSearchService.new(toolable, llm_context:)
    result = service.search(query, limit: effective_limit)
    format_result(result)
  rescue StandardError => e
    Rails.logger.error "[#{self.class.name}] Query failed for tool '#{@tool_record.name}': #{e.message}"
    "I couldn't execute that search. Error: #{e.message}"
  end

  private

  def toolable
    @tool_record.toolable
  end

  def sanitize_tool_name(prefix)
    base = @tool_record.name
                       .unicode_normalize(:nfkd)
                       .encode("ASCII", replace: "")
                       .gsub(/[^a-zA-Z0-9_-]/, "_").squeeze("_")
                       .gsub(/\A_|_\z/, "")
                       .downcase

    "#{prefix}_#{base}"
  end

  def resolve_llm_context
    llm_conn = toolable.llm_connector
    return nil if llm_conn.blank?

    llm_conn.build_context
  end

  def format_result(result)
    return "No relevant chunks found." if result.blank?

    result.to_json
  end
end
