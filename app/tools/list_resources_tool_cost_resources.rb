# frozen_string_literal: true

module ListResourcesToolCostResources
  private

  def cost_limits
    scope = tenant.cost_limits.ordered
    return "No cost limits configured." if scope.empty?

    lines = ["## Cost Limits"]
    scope.each do |limit|
      result = Costs::LimitEvaluator.call(limit)
      lines << "- `#{limit.id}` — #{limit.name} — #{result.status} — #{limit.target_type}: #{limit.target_label}"
    end
    lines.join("\n")
  end

  def cost_target_types
    lines = ["## Cost Target Types"]
    CostLimit::TARGET_TYPES.each do |target_type|
      lines << "- `#{target_type}` — #{cost_target_type_hint(target_type)}"
    end
    lines << "Periods: #{CostLimit::PERIODS.map { |period| "`#{period}`" }.join(", ")}"
    lines << "Enforcement modes: #{CostLimit::ENFORCEMENT_MODES.map { |mode| "`#{mode}`" }.join(", ")}"
    lines.join("\n")
  end

  def cost_target_type_hint(target_type)
    {
      "tenant" => "tenant-wide; do not pass target_id or target_key",
      "operation" => "pass the operation ID as target_id",
      "user" => "pass the user ID as target_id",
      "agent" => "pass the agent ID as target_id",
      "mission" => "pass the mission ID as target_id",
      "channel" => "pass the channel ID as target_id",
      "model" => "pass the model record ID as target_id",
      "execution_context" => "pass a chat execution context as target_key",
    }.fetch(target_type)
  end
end
