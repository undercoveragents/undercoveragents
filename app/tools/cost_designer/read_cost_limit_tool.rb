# frozen_string_literal: true

module CostDesigner
  class ReadCostLimitTool < RubyLLM::Tool
    include CostLimitLookup

    description "Read one cost limit or list all cost limits with current spend status."

    param :cost_limit_id,
          desc: "Optional cost limit numeric ID or exact name. Omit to list every limit in the current tenant.",
          required: false

    def initialize(runtime_context:)
      super()
      @runtime_context = runtime_context
    end

    def name = "read_cost_limit"

    def execute(cost_limit_id: nil)
      limit = resolve_cost_limit(cost_limit_id)
      return render_all_limits if limit.nil?

      render_limit(limit)
    rescue ActiveRecord::RecordNotFound => e
      "Error: #{e.message}"
    end

    private

    def render_all_limits
      limits = tenant.cost_limits.ordered
      return "No cost limits configured." if limits.empty?

      lines = ["## Cost Limits"]
      limits.each { |limit| lines << limit_line(limit) }
      lines.join("\n")
    end

    def render_limit(limit)
      result = Costs::LimitEvaluator.call(limit)
      [
        "## Cost Limit",
        "- ID: `#{limit.id}`",
        "- Name: #{limit.name}",
        "- Target: #{limit.target_type.humanize} — #{limit.target_label}",
        "- Operation scope: #{limit.operation&.name || "All operations"}",
        "- Period: #{result.period.label}",
        "- Status: #{result.status}",
        "- Spend: #{format_cost(result.spend)} / #{format_cost(result.amount)} (#{result.percent_used}%)",
        "- Remaining: #{format_cost(result.remaining)}",
        "- Warning threshold: #{limit.warning_threshold_percent}%",
        "- Enforcement: #{limit.enforcement_mode}",
        "- Enabled: #{limit.enabled?}",
        editable_fields,
      ].join("\n")
    end

    def limit_line(limit)
      result = Costs::LimitEvaluator.call(limit)
      "- `#{limit.id}` — #{limit.name} — #{result.status} — " \
        "#{format_cost(result.spend)} / #{format_cost(result.amount)} — #{limit.target_type}: #{limit.target_label}"
    end

    def editable_fields
      "\nEditable fields: name, description, target_type, target_id, target_key, operation_id, period, amount_usd, " \
        "warning_threshold_percent, enforcement_mode, enabled."
    end

    def format_cost(amount)
      format("$%.6f", amount.to_d)
    end
  end
end
