# frozen_string_literal: true

# Shared concern for RAG search configuration.
#
# Provides common constants, validations, and methods for models that
# support vector similarity search (Tools::RagQuery, Tools::RagFlow).
#
# Including models must have these columns:
#   - distance_method  (string)
#   - max_distance     (float)
#   - results_limit    (integer)
#   - custom_instructions (text)
#   - document_fields  (jsonb array)
#
# Including models must implement:
#   - #sql_database          → Connectors::SqlDatabase
#   - #chunks_table          → String
#   - #documents_table       → String
#   - #embedding_field       → String
#   - #chunk_content_field   → String
#   - #document_reference_field → String
#   - #embedding_model_id    → String
#   - #llm_connector         → Connector (LLM Provider)
#
module Tools
  module RagSearchable
    extend ActiveSupport::Concern

    DEFAULT_TOOL_PROMPT = "Search a knowledge base using semantic similarity. " \
                          "Provide a natural language query to find relevant document chunks."

    DISTANCE_METHODS = ["cosine", "l2", "inner_product"].freeze
    DISTANCE_OPERATORS = {
      "cosine" => "<=>",
      "l2" => "<->",
      "inner_product" => "<#>",
    }.freeze
    MAX_RESULTS_LIMIT = 100

    included do
      validates :distance_method, presence: true, inclusion: { in: DISTANCE_METHODS }
      validates :max_distance, numericality: { greater_than: 0.0, less_than_or_equal_to: 2.0 }, allow_nil: true
      validates :results_limit, presence: true,
                                numericality: { only_integer: true, greater_than: 0,
                                                less_than_or_equal_to: MAX_RESULTS_LIMIT, }
      validates :custom_instructions, length: { maximum: 10_000 }
    end

    def distance_operator
      DISTANCE_OPERATORS.fetch(distance_method, "<=>")
    end

    def effective_instructions
      custom_instructions.presence || DEFAULT_TOOL_PROMPT
    end

    def selected_document_fields
      return [] unless document_fields.is_a?(Array)

      document_fields.filter_map { |f| f.is_a?(Hash) ? (f["name"] || f[:name]) : f }
    end
  end
end
