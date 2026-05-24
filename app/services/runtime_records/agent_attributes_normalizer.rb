# frozen_string_literal: true

module RuntimeRecords
  class AgentAttributesNormalizer
    def self.call(record:, attributes:)
      new(record:, attributes:).call
    end

    def initialize(record:, attributes:)
      @record = record
      @attributes = attributes.to_h.stringify_keys
    end

    def call
      clear_reasoning_budget_when_disabled
      normalize_agent_type
      normalize_runtime_tool_keys
      attributes
    end

    private

    attr_reader :record, :attributes

    def clear_reasoning_budget_when_disabled
      return unless attributes["thinking_effort"].to_s == "none"

      attributes["thinking_budget"] = nil
    end

    def normalize_agent_type
      return unless attributes.key?("agent_type")
      return unless AgentConfiguration.provider_agent_type?(attributes["agent_type"])

      attributes["agent_type"] = AgentConfiguration::DEFAULT_AGENT_TYPE
    end

    def normalize_runtime_tool_keys
      return unless attributes.key?("runtime_tool_keys")

      if record.builtin?
        attributes.delete("runtime_tool_keys")
      else
        attributes["runtime_tool_keys"] = Array(attributes["runtime_tool_keys"]) & BuiltinTools::Registry.user_assignable_keys
      end
    end
  end
end
