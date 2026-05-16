# frozen_string_literal: true

module Capabilities
  class Memory
    include UndercoverAgents::PluginSystem::Configurator
    include CapabilityPlugin

    DEFAULT_MODEL_ID = "text-embedding-3-small"
    DEFAULT_EMBEDDING_DIMENSIONS = 1536
    AGENT_DESIGNER_FIELDS = [
      {
        name: "model_id",
        type: "string",
        default: DEFAULT_MODEL_ID,
        description: "Embedding model id for archival memory indexing and search.",
      },
      {
        name: "embedding_dimensions",
        type: "integer",
        default: DEFAULT_EMBEDDING_DIMENSIONS,
        description: "Embedding vector size expected from the selected model.",
      },
      {
        name: "auto_bootstrap",
        type: "boolean",
        default: true,
        description: "Bootstrap default memory blocks automatically on first chat.",
      },
      {
        name: "llm_connector_id",
        type: "integer",
        default: nil,
        description: "Optional LLM provider connector id used for embeddings and archival memory search.",
      },
    ].freeze
    AGENT_DESIGNER_NOTES = [
      "When llm_connector_id is blank, archival memory insert/search tools stay unavailable.",
    ].freeze

    attribute :model_id, :string, default: DEFAULT_MODEL_ID
    attribute :embedding_dimensions, :integer, default: DEFAULT_EMBEDDING_DIMENSIONS
    attribute :auto_bootstrap, :boolean, default: true
    attribute :llm_connector_id, :integer

    key "memory"
    label "Memory"
    icon "fa-solid fa-brain"
    description "Letta-inspired memory: always-in-context core memory blocks " \
                "and pgvector archival memory for long-term semantic retrieval."

    validates :model_id, presence: true
    validates :embedding_dimensions, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validate :llm_connector_must_be_llm_provider

    def self.permitted_params(raw)
      raw.permit(:model_id, :embedding_dimensions, :auto_bootstrap, :llm_connector_id)
    end

    def self.agent_designer_fields = AGENT_DESIGNER_FIELDS

    def self.agent_designer_notes = AGENT_DESIGNER_NOTES

    # Called by HasCapabilities#capability_tools — returns RubyLLM::Tool instances
    # for memory manipulation during chat.
    #
    # User context is extracted from +parent_chat+. Without a user, no memory
    # tools are provided (prevents accidental cross-user contamination).
    def tools_for(agent:, parent_chat: nil)
      user = parent_chat&.user
      return [] unless user

      # Lazy per-user bootstrap on first chat if auto_bootstrap is enabled.
      if auto_bootstrap && !agent.memory_configured_for?(user)
        Capabilities::Memory::Bootstrapper.new(agent, user:).bootstrap!
      end

      tools = [
        Capabilities::Memory::MemoryReplaceTool.for_agent(agent, user:),
        Capabilities::Memory::MemoryInsertTool.for_agent(agent, user:),
      ]

      # Archival memory tools require an embedding connector.
      if embedding_connector.present?
        service = build_embedding_service
        tools << Capabilities::Memory::ArchivalMemoryInsertTool.for_agent(agent, user:, embedding_service: service)
        tools << Capabilities::Memory::ArchivalMemorySearchTool.for_agent(agent, user:, embedding_service: service)
      end

      tools
    end

    # Called by HasCapabilities#capability_system_prompt_additions — returns
    # the memory blocks XML for injection into the system prompt.
    # +user+ is required; returns nil if no user or user has no bootstrapped blocks.
    def system_prompt_addition_for(agent:, user: nil)
      return nil unless user && agent.memory_configured_for?(user)

      Capabilities::Memory::ContextBuilder.new(agent, user:).build
    end

    # Called after the capability is saved as enabled.
    # Bootstrapping is deferred to first chat (per-user, lazy) so there is
    # nothing to do here without a user context.
    def after_capability_enabled(_agent)
      nil
    end

    def summary
      parts = [model_id]
      parts << "auto-bootstrap" if auto_bootstrap
      conn = embedding_connector
      parts << (conn ? conn.name : "no connector")
      parts.join(" · ")
    end

    def embedding_connector
      find_connector(llm_connector_id)
    end

    def form_locals
      { available_llm_connectors: connector_scope.llm_providers.enabled.ordered }
    end

    private

    def llm_connector_must_be_llm_provider
      return if llm_connector_id.blank?
      return if embedding_connector&.connector_type == "llm_provider"

      errors.add(:llm_connector_id, "must be an LLM Provider connector")
    end

    def build_embedding_service
      Capabilities::Memory::EmbeddingService.new(
        connector: embedding_connector,
        model: model_id,
      )
    end
  end
end
