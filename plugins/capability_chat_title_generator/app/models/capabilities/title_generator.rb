# frozen_string_literal: true

module Capabilities
  class TitleGenerator
    include UndercoverAgents::PluginSystem::Configurator
    include CapabilityPlugin

    LLM_CONFIG_SOURCES = ["inherit", "custom"].freeze
    DEFAULT_MAX_LENGTH = 30
    DEFAULT_MAX_TURNS = 3
    DEFAULT_TEMPERATURE = 0.7
    AGENT_DESIGNER_FIELDS = [
      {
        name: "max_length",
        type: "integer",
        default: DEFAULT_MAX_LENGTH,
        description: "Maximum generated title length in characters.",
      },
      {
        name: "max_turns",
        type: "integer",
        default: DEFAULT_MAX_TURNS,
        description: "How many recent conversation turns to use for title generation.",
      },
      {
        name: "llm_config_source",
        type: "string",
        default: "inherit",
        allowed_values: LLM_CONFIG_SOURCES,
        description: "Use 'inherit' to reuse the agent LLM config or 'custom' for a dedicated model.",
      },
      {
        name: "llm_connector_id",
        type: "integer",
        default: nil,
        required_when: "llm_config_source is 'custom'",
        description: "LLM provider connector id for custom title generation.",
      },
      {
        name: "model_id",
        type: "string",
        default: nil,
        required_when: "llm_config_source is 'custom'",
        description: "Model id to use when llm_config_source is 'custom'.",
      },
      {
        name: "temperature",
        type: "float",
        default: DEFAULT_TEMPERATURE,
        required_when: "llm_config_source is 'custom'",
        description: "Sampling temperature for custom title generation.",
      },
    ].freeze
    AGENT_DESIGNER_NOTES = [
      "Switching to 'inherit' ignores custom connector, model, and temperature fields.",
    ].freeze

    attribute :max_length, :integer, default: DEFAULT_MAX_LENGTH
    attribute :max_turns, :integer, default: DEFAULT_MAX_TURNS
    attribute :llm_config_source, :string, default: "inherit"
    attribute :llm_connector_id, :integer
    attribute :model_id, :string
    attribute :temperature, :float, default: DEFAULT_TEMPERATURE

    key "chat_title_generator"
    label "Chat Title Generator"
    icon "fa-solid fa-heading"
    description "Generate short chat titles from recent conversation context."

    validates :max_length, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 200 }
    validates :max_turns, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 50 }
    validates :llm_config_source, inclusion: { in: LLM_CONFIG_SOURCES }
    validates :model_id, presence: true, if: :use_custom_llm_config?
    validates :temperature,
              numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 2.0 },
              if: :use_custom_llm_config?
    validate :llm_connector_must_be_llm_provider, if: :use_custom_llm_config?

    def self.permitted_params(raw)
      raw.permit(:max_length, :max_turns, :llm_config_source, :llm_connector_id, :model_id, :temperature)
    end

    def self.event_handler_class
      Capabilities::TitleGenerationService
    end

    def self.agent_designer_fields = AGENT_DESIGNER_FIELDS

    def self.agent_designer_notes = AGENT_DESIGNER_NOTES

    def use_custom_llm_config?
      llm_config_source == "custom"
    end

    def inherit_llm_config?
      llm_config_source == "inherit"
    end

    def summary
      parts = ["max #{max_length} chars", "#{max_turns} turns"]
      parts << (use_custom_llm_config? ? "custom LLM" : "inherit LLM")
      parts.join(" · ")
    end

    def to_configuration
      config = super
      return config if use_custom_llm_config?

      config.except("llm_connector_id", "model_id", "temperature")
    end

    def resolve_connector(agent)
      if use_custom_llm_config? && llm_connector_id.present?
        find_connector(llm_connector_id)
      else
        agent&.resolved_llm_connector
      end
    end

    def resolve_model_id(agent)
      use_custom_llm_config? ? model_id : agent&.resolved_model_id
    end

    def resolve_temperature(agent)
      use_custom_llm_config? ? temperature : agent&.temperature
    end

    private

    def llm_connector_must_be_llm_provider
      return if llm_connector_id.blank?

      connector = find_connector(llm_connector_id)
      return if connector&.connector_type == "llm_provider"

      errors.add(:llm_connector_id, "must be an LLM Provider connector")
    end
  end
end
