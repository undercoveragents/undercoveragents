# frozen_string_literal: true

module Missions
  # Flow snapshot normalization plus graph/context construction for mission runs.
  module RunnerExecutionSetup
    private

    def restore_execution_context(run)
      ExecutionContext.restore(mission_run: run, state: run.execution_state)
    end

    # :nocov:
    def build_execution_context(run, variables: {}, trigger_data: {})
      context = ExecutionContext.new(
        mission_run: run,
        variables: variables.merge("_nesting_depth" => variables.fetch("_nesting_depth", 0)),
      )
      seed_global_variables(context, normalized_flow_snapshot(run))
      context.set_variable("_trigger_data", trigger_data)
      trigger_data.each { |key, value| context.set_variable(key, value) }
      context
    end
    # :nocov:

    def build_graph(run)
      FlowGraph.new(normalized_flow_snapshot(run))
    end

    def normalized_flow_snapshot(run)
      Missions::FlowDataSanitizer.sanitize(run.flow_snapshot)
    end

    def seed_global_variables(context, flow_snapshot)
      (flow_snapshot["global_variables"] || []).each do |var|
        context.set_variable(var["key"], cast_global_variable(var["value"], var["type"]))
      end
    end

    def cast_global_variable(value, type)
      case type
      when "number" then value.to_s.include?(".") ? value.to_f : value.to_i
      when "boolean" then ActiveModel::Type::Boolean.new.cast(value)
      else value.to_s
      end
    end
  end
end
