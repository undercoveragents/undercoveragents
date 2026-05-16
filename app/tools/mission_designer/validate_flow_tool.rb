# frozen_string_literal: true

module MissionDesigner
  # Validates the current mission flow and reports all errors.
  # Delegates to Missions::FlowValidator for reusable validation logic.
  class ValidateFlowTool < BaseTool
    description "Validates the flow and reports config errors, structural issues, warnings, " \
                "and targeted recovery hints."

    param :mission_id,
          desc: "Optional mission ID or slug to validate. Use this after creating a mission in the same turn.",
          required: false

    def name
      "validate_flow"
    end

    def execute(mission_id: nil)
      mission = resolve_target_mission(mission_id)
      result = Missions::FlowValidator.call(mission)
      format_result(result)
    rescue StandardError => e
      "Error validating flow: #{e.message}"
    end

    private

    def format_result(result)
      parts = []
      config_errors = result.config_errors || {}

      append_config_errors(parts, config_errors) if config_errors.any?
      append_structural_issues(parts, result.structural_issues) if result.structural_issues.any?
      append_warnings(parts, result.warnings) if result.warnings.any?
      append_recovery_hints(parts, config_errors) if config_errors.any?

      header = if result.valid?
                 "Flow is valid. #{result.node_count} nodes, #{result.edge_count} edges.\n"
               else
                 "Flow has errors that should be fixed:\n"
               end
      parts.unshift(header)
      parts.join("\n")
    end

    def append_config_errors(parts, config_errors)
      parts << "## Configuration Errors"
      config_errors.each do |node_id, errs|
        errs.each do |err|
          label = err[:node_name] ? "#{err[:node_name]} (#{err[:node_type]})" : node_id
          parts << "- **#{label}**: #{err[:field]} #{err[:message]}"
        end
      end
      parts << ""
    end

    def append_structural_issues(parts, issues)
      parts << "## Structural Issues"
      issues.each { |issue| parts << "- #{issue}" }
      parts << ""
    end

    def append_warnings(parts, warnings)
      parts << "## Warnings"
      warnings.each { |w| parts << "- #{w}" }
      parts << ""
    end

    def append_recovery_hints(parts, config_errors)
      hints = recovery_hints(config_errors)

      return if hints.empty?

      parts << "## Recovery Hints"
      hints.each { |hint| parts << "- #{hint}" }
      parts << ""
    end

    def recovery_hints(config_errors)
      fields_and_messages = config_errors.values.flatten.map { |error| [error[:field].to_s, error[:message].to_s] }

      [].tap do |hints|
        hints << unknown_variable_hint if unknown_variable_hint?(fields_and_messages)
        hints << blank_global_hint if blank_global_hint?(fields_and_messages)
        hints << assignment_shape_hint if assignment_shape_hint?(fields_and_messages)
      end
    end

    def unknown_variable_hint?(fields_and_messages)
      fields_and_messages.any? do |_field, message|
        message.match?(/unknown variable|unknown output|references unknown variable/i)
      end
    end

    def blank_global_hint?(fields_and_messages)
      fields_and_messages.any? do |_field, message|
        message.match?(/blank global variable|globals are seeded inputs only/i)
      end
    end

    def assignment_shape_hint?(fields_and_messages)
      fields_and_messages.any? { |field, _message| field == "assignments" }
    end

    def unknown_variable_hint
      "Unknown variable/output references: call `list_node_variables` on the consuming node " \
        "and reuse one returned identifier exactly. Do not use temp_id, raw node IDs, or " \
        "guessed normalized labels."
    end

    def blank_global_hint
      "Globals are seeded inputs/constants only. Remove blank or placeholder globals that " \
        "shadow computed values and use node outputs or a `set_variable` node instead."
    end

    def assignment_shape_hint
      "`set_variable` expects `assignments` as an object map like {\"summary\":\"'PASS'\"}. " \
        "If you used a `variables` array or another alias, rewrite it as `assignments`."
    end
  end
end
