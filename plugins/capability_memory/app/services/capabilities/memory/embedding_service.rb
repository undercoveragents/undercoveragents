# frozen_string_literal: true

module Capabilities
  class Memory
    # Wraps RubyLLM.embed() — matching the existing RAG infrastructure pattern.
    #
    # Usage:
    #   service = EmbeddingService.new(connector:, model: "text-embedding-3-small")
    #   vector = service.embed("Some text to embed")
    #   # => Array<Float> of length matching the model's dimensions
    class EmbeddingService
      DEFAULT_MODEL = "text-embedding-3-small"

      # @param connector [Connector] LLM provider connector for embedding API access
      # @param model [String] embedding model ID
      def initialize(connector:, model: DEFAULT_MODEL)
        @connector = connector
        @model = model
      end

      # @param text [String] the text to embed
      # @return [Array<Float>] embedding vector
      def embed(text)
        raise ArgumentError, "text cannot be blank" if text.blank?

        context = @connector.configurator.build_context
        response = RubyLLM.embed(text, model: @model, context:)
        response.vectors.first
      end
    end
  end
end
