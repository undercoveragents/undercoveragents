# frozen_string_literal: true

module Costs
  class MessageCostSnapshotter
    USD = "USD"
    EMPTY_BREAKDOWN = {
      input_cost_usd: nil,
      cached_input_cost_usd: nil,
      cache_creation_cost_usd: nil,
      output_cost_usd: nil,
      cost_usd: nil,
      cost_pricing_snapshot: {},
      cost_calculated_at: nil,
    }.freeze

    def self.call(message)
      new(message).call
    end

    def initialize(message)
      @message = message
    end

    def call
      breakdown = @message.calculate_cost_breakdown
      return clear_snapshot unless breakdown

      assign_snapshot(breakdown)
    end

    private

    def clear_snapshot
      @message.assign_attributes(EMPTY_BREAKDOWN.merge(cost_currency: USD))
    end

    def assign_snapshot(breakdown)
      @message.assign_attributes(
        input_cost_usd: breakdown.fetch(:input),
        cached_input_cost_usd: breakdown.fetch(:cached_input),
        cache_creation_cost_usd: breakdown.fetch(:cache_creation),
        output_cost_usd: breakdown.fetch(:output),
        cost_usd: breakdown.fetch(:total),
        cost_currency: USD,
        cost_pricing_snapshot: breakdown.fetch(:pricing),
        cost_calculated_at: Time.current,
      )
    end
  end
end
