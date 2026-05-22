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
      attributes
    end

    private

    attr_reader :record, :attributes

    def clear_reasoning_budget_when_disabled
      return unless attributes["thinking_effort"].to_s == "none"

      attributes["thinking_budget"] = nil
    end
  end
end
