# frozen_string_literal: true

module Admin
  module PluginsHelper
    CATEGORY_LABELS = {
      rag_input: "RAG Source",
      rag_chunking: "RAG Chunking",
      rag_embedding: "RAG Embedding",
      rag_storage: "RAG Storage",
    }.freeze

    def plugin_category_labels(plugin)
      labels = Array(plugin.category).map do |category|
        CATEGORY_LABELS[category.to_sym] || category.to_s.humanize.titleize
      end

      labels.sort
    end
  end
end
