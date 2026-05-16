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
      normalize_reasoning_disable
      clear_reasoning_budget_when_disabled
      attributes
    end

    private

    attr_reader :record, :attributes

    def normalize_reasoning_disable
      return unless attributes.key?("thinking_effort")
      return if attributes["thinking_effort"].present?
      return unless deepseek_agent?

      attributes["thinking_effort"] = "none"
    end

    def clear_reasoning_budget_when_disabled
      return unless attributes["thinking_effort"].to_s == "none"

      attributes["thinking_budget"] = nil
    end

    def deepseek_agent?
      model_id = attributes["model_id"].presence || record.model_id
      model = Model.find_by(model_id:)

      model&.provider.to_s == "deepseek"
    end
  end
end
