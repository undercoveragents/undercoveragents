# frozen_string_literal: true

class CostAnalysisPresenter
  DIMENSIONS = ["operation", "user", "agent", "mission", "channel", "model", "execution_context"].freeze

  attr_reader :tenant, :operation, :period, :period_result, :summary, :cost_by_day, :dimension_groups,
              :limit_results, :recent_expensive_messages

  def initialize(tenant:, operation: nil, period: "rolling_30_days")
    @tenant = tenant
    @operation = operation
    @period = period
    @period_result = Costs::Period.resolve(period)
    query = Costs::AggregateQuery.new(message_scope)
    @summary = query.summary
    @cost_by_day = query.cost_by_day
    @dimension_groups = DIMENSIONS.index_with { |dimension| query.by_dimension(dimension) }
    @limit_results = load_limit_results
    @recent_expensive_messages = load_recent_expensive_messages
  end

  def active_limit_count
    limit_results.count { |result| result.limit.enabled? }
  end

  def warning_limit_count
    limit_results.count(&:warning?)
  end

  def exceeded_limit_count
    limit_results.count(&:exceeded?)
  end

  def projected_monthly_cost
    return summary.total_cost if period_result.starts_at.blank?

    elapsed_days = [(Time.current.to_date - period_result.starts_at.to_date).to_i + 1, 1].max
    (summary.total_cost / elapsed_days) * Time.current.end_of_month.day
  end

  private

  def message_scope
    Costs::Scope.new(tenant:, operation:, range: period_result.range).messages
  end

  def load_limit_results
    limits = tenant.cost_limits.enabled.ordered
    limits = limits.where(operation:) if operation
    limits.map { |limit| Costs::LimitEvaluator.call(limit) }
  end

  def load_recent_expensive_messages
    message_scope.includes(:chat, :model)
                 .order(Arel.sql("COALESCE(messages.cost_usd, 0) DESC"), created_at: :desc)
                 .limit(8)
  end
end
