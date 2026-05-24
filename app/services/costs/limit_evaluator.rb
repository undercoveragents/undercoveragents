# frozen_string_literal: true

module Costs
  class LimitEvaluator
    Result = Data.define(
      :limit,
      :period,
      :spend,
      :amount,
      :remaining,
      :percent_used,
      :status,
      :hard_stop,
    ) do
      def exceeded? = status == "exceeded"
      def warning? = status == "warning"
      def healthy? = status == "healthy"
    end

    def self.call(limit)
      new(limit).call
    end

    def initialize(limit)
      @limit = limit
    end

    def call
      amount = BigDecimal(@limit.amount_usd.to_s)
      spend = Costs::AggregateQuery.new(Costs::Scope.new(tenant: @limit.tenant).for_limit(@limit)).summary.total_cost

      Result.new(
        limit: @limit,
        period: Costs::Period.resolve(@limit.period),
        spend:,
        amount:,
        remaining: [amount - spend, BigDecimal("0")].max,
        percent_used: amount.positive? ? ((spend / amount) * 100).round(1) : 0,
        status: status_for(spend, amount),
        hard_stop: @limit.hard_stop?,
      )
    end

    private

    def status_for(spend, amount)
      return "exceeded" if spend >= amount
      return "warning" if spend >= amount * @limit.warning_fraction

      "healthy"
    end
  end
end
