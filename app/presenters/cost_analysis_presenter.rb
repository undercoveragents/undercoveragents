# frozen_string_literal: true

class CostAnalysisPresenter
  DIMENSIONS = ["operation", "user", "agent", "mission", "channel", "model", "execution_context"].freeze
  FilterSet = Data.define(:execution_context, :user, :agent, :model)

  attr_reader :tenant, :operation, :period, :period_result, :summary, :cost_by_day, :dimension_groups,
              :limit_results, :recent_expensive_messages, :filters

  def initialize(tenant:, operation: nil, period: "rolling_30_days", filters: FilterSet.new(
    execution_context: nil,
    user: nil,
    agent: nil,
    model: nil,
  ))
    @tenant = tenant
    @operation = operation
    @period = period
    @filters = filters
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

  def execution_context = filters.execution_context

  def user = filters.user

  def agent = filters.agent

  def model = filters.model

  def message_scope
    filter_steps.reduce(Costs::Scope.new(tenant:, operation:, range: period_result.range).messages) do |scope, step|
      step.call(scope)
    end
  end

  def filter_steps
    [
      (->(scope) { scope.where(chats: { execution_context: }) } if execution_context.present?),
      (->(scope) { scope.where(chats: { user_id: user.id }) } if user.present?),
      (->(scope) { scope.where(chats: { agent_id: agent.id }) } if agent.present?),
      (->(scope) { scope.where("messages.model_id = :id OR chats.model_id = :id", id: model.id) } if model.present?),
    ].compact
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
