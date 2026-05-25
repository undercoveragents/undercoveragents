# frozen_string_literal: true

module CostDesigner
  class ReadCostAnalysisTool < RubyLLM::Tool
    description "Read cost dashboard summaries, top spend dimensions, and active limit health."

    param :period,
          desc: "Optional period: day, week, month, quarter, year, rolling_7_days, rolling_30_days, or all_time.",
          required: false
    param :operation_id,
          desc: "Optional operation numeric ID, slug, or exact name. Omit for tenant-wide analysis.",
          required: false

    def initialize(runtime_context:)
      super()
      @runtime_context = runtime_context
    end

    def name = "read_cost_analysis"

    def execute(period: "rolling_30_days", operation_id: nil)
      presenter = CostAnalysisPresenter.new(
        tenant: @runtime_context.tenant,
        operation: resolve_operation(operation_id),
        period: normalized_period(period),
      )

      render_summary(presenter)
    rescue ActiveRecord::RecordNotFound, ArgumentError => e
      "Error: #{e.message}"
    end

    private

    def render_summary(presenter)
      [
        "## Cost Analysis",
        "- Period: #{presenter.period_result.label}",
        ("- Operation: #{presenter.operation.name}" if presenter.operation),
        "- Total spend: #{format_cost(presenter.summary.total_cost)}",
        "- Projected monthly spend: #{format_cost(presenter.projected_monthly_cost)}",
        "- Input tokens: #{presenter.summary.input_tokens}",
        "- Output tokens: #{presenter.summary.output_tokens}",
        "- Chats: #{presenter.summary.chat_count}",
        "- Average chat cost: #{format_cost(presenter.summary.average_chat_cost)}",
        limit_summary(presenter),
        dimension_summary(presenter),
      ].compact.join("\n")
    end

    def limit_summary(presenter)
      return "- Active limits: none" if presenter.limit_results.empty?

      "- Active limits: #{presenter.active_limit_count} " \
        "(#{presenter.warning_limit_count} warning, #{presenter.exceeded_limit_count} exceeded)"
    end

    def dimension_summary(presenter)
      lines = ["\n## Top Spend"]
      presenter.dimension_groups.each do |dimension, groups|
        next if groups.empty?

        lines << "### #{dimension.humanize}"
        groups.first(5).each { |group| lines << "- #{group.label}: #{format_cost(group.cost)}" }
      end
      lines.join("\n")
    end

    def normalized_period(period)
      value = period.to_s.presence || "rolling_30_days"
      CostLimit::PERIODS.include?(value) ? value : "rolling_30_days"
    end

    def resolve_operation(identifier)
      value = identifier.to_s.strip
      return nil if value.blank? || value == "all"

      scope = @runtime_context.tenant.operations
      scope.find_by(id: value) || scope.find_by(slug: value) ||
        scope.find_by("LOWER(operations.name) = ?", value.downcase) ||
        raise(ActiveRecord::RecordNotFound, "Operation '#{identifier}' was not found.")
    end

    def format_cost(amount)
      format("$%.6f", amount.to_d)
    end
  end
end
