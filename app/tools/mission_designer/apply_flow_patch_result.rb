# frozen_string_literal: true

module MissionDesigner
  module ApplyFlowPatchResult
    private

    def broadcast_arrange(mission)
      Turbo::StreamsChannel.broadcast_append_to(
        "mission_flow_#{mission.id}",
        target: "mission-flow-updates",
        html: "<div data-arrange=\"true\"></div>",
      )
    rescue StandardError => e
      Rails.logger.warn("ApplyFlowPatchTool arrange broadcast failed: #{e.message}")
    end

    def format_result(state)
      parts = ["## Patch Applied", "- Operations: #{state.ops.size}", "- Errors: #{state.errors.size}"]
      append_temp_ids(parts, state.temp_ids, state.editor.read_flow[:nodes].index_by { |node| node[:id] })
      append_reference_rewrites(parts, state.rewritten_temp_ids)
      append_errors(parts, state.errors)
      parts << ""
      parts << format_validation(Missions::FlowValidator.call(state.mission.reload))
      parts.join("\n")
    end

    def append_temp_ids(parts, temp_ids, nodes_by_id)
      return if temp_ids.empty?

      parts << ""
      parts << "## Assigned Node IDs"
      parts << "Use the reported variable prefix for variables and templates."
      parts << "`temp_id` is only for same-patch node and edge references."
      temp_ids.each do |temp, real|
        variable_name = nodes_by_id.dig(real, :variable_name)
        suffix = variable_name.present? ? " (var_prefix: `#{variable_name}`)" : ""
        parts << "- `#{temp}` → `#{real}`#{suffix}"
      end
    end

    def append_reference_rewrites(parts, rewritten_temp_ids)
      return if rewritten_temp_ids.empty?

      parts << ""
      parts << "## Normalized Variable References"
      rewritten_temp_ids.each do |temp_id, variable_name|
        parts << "- Reused `#{temp_id}` as the variable prefix and normalized it to `#{variable_name}`."
      end
    end

    def append_errors(parts, errors)
      return if errors.empty?

      parts << ""
      parts << "## Errors"
      errors.each { |msg| parts << "- #{msg}" }
    end

    def format_validation(result)
      lines = result.valid? ? valid_validation_lines(result) : invalid_validation_lines(result)
      append_warnings(lines, result.warnings)
      lines.join("\n")
    end

    def valid_validation_lines(result)
      ["## Validation", "Flow is valid (#{result.node_count} nodes, #{result.edge_count} edges)."].tap do |messages|
        if result.warnings.empty?
          messages << "The patch response already includes validation; only call `validate_flow` " \
                      "if you need a separate diagnostic pass after more edits or while debugging."
        end
      end
    end

    def invalid_validation_lines(result)
      ["## Validation Issues"].tap do |messages|
        result.config_errors.each do |node_id, errs|
          errs.each { |err| messages << "- Config `#{node_id}` #{err[:field]}: #{err[:message]}" }
        end
        result.structural_issues.each { |msg| messages << "- Structural: #{msg}" }
      end
    end

    def append_warnings(lines, warnings)
      return if warnings.empty?

      lines << ""
      lines << "## Warnings"
      warnings.each { |warning| lines << "- #{warning}" }
    end
  end
end
