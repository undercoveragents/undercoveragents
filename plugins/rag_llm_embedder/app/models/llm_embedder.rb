# frozen_string_literal: true

module RagSteps
  # Generates vector embeddings for document chunks via an LLM provider.
  # Uses token-aware batching to respect API context-length limits.
  class LlmEmbedder
    include UndercoverAgents::PluginSystem::Configurator
    include RagStepPlugin

    MAX_BATCH_SIZE = 2000
    MAX_TOKENS_PER_BATCH = 100_000
    APPROX_CHARS_PER_TOKEN = 4

    attribute :llm_connector_id, :integer
    attribute :model_id, :string
    attribute :batch_size, :integer, default: 100
    attribute :max_tokens_per_batch, :integer, default: 6000
    attribute :dimensions, :integer

    validates :model_id, presence: true, length: { maximum: 200 }
    validates :batch_size, presence: true,
                           numericality: { only_integer: true, greater_than: 0,
                                           less_than_or_equal_to: MAX_BATCH_SIZE, }
    validates :max_tokens_per_batch, presence: true,
                                     numericality: { only_integer: true, greater_than: 0,
                                                     less_than_or_equal_to: MAX_TOKENS_PER_BATCH, }
    validates :dimensions, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validate :llm_connector_must_be_llm_provider

    # ── Step Type Protocol ────────────────────────────────────────

    key "llm_embedder"
    label "LLM Embedder"
    icon "fa-solid fa-vector-square"
    stage :embedding
    description "Generate embeddings using an LLM provider. Supports token-aware batching for efficient processing."

    def self.permitted_params(params)
      params.expect(
        llm_embedder: [:llm_connector_id, :model_id, :batch_size, :max_tokens_per_batch, :dimensions],
      )
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    # ── Connector Helper ──────────────────────────────────────────

    def llm_connector
      return @llm_connector if defined?(@llm_connector)

      @llm_connector = find_connector(llm_connector_id)
    end

    # ── Execution ─────────────────────────────────────────────────

    def execute(documents, context)
      Rag::Steps::LlmEmbedderExecutor.new(self, context).call(documents)
    end

    def validate_configuration!
      raise "LLM connector is required" if llm_connector.blank?
      raise "Model ID is required" if model_id.blank?
    end

    def summary
      "#{model_id} via #{llm_connector&.name || "unknown"} (batch: #{batch_size})"
    end

    private

    def llm_connector_must_be_llm_provider
      return if llm_connector_id.blank?

      conn = llm_connector
      return errors.add(:llm_connector_id, "connector not found") if conn.nil?
      return if conn.connector_type == "llm_provider"

      errors.add(:llm_connector_id, "must be an LLM Provider connector")
    end
  end
end
