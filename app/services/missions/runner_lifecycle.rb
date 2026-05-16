# frozen_string_literal: true

module Missions
  # Run bootstrap, context seeding/restoration, and top-level lifecycle flow.
  module RunnerLifecycle
    private

    def execute_run(run, variables: {}, trigger_data: {})
      graph = build_graph(run)
      context = build_execution_context(run, variables:, trigger_data:)

      execute_with_lifecycle(run, graph, context, update_attrs: { started_at: Time.current })
    end

    def continue_saved_run(run, allowed_statuses:, invalid_message:, update_attrs: {})
      raise ExecutionError, invalid_message unless allowed_run_status?(run, allowed_statuses)

      execute_with_lifecycle(
        run,
        build_graph(run),
        restore_execution_context(run),
        start_node_id: run.current_node_id,
        update_attrs:,
      )
    end

    def execute_with_lifecycle(run, graph, context, start_node_id: nil, update_attrs: {})
      begin
        run.update!(status: :running, **update_attrs)
        start_node_id ? execute_from(run, graph, context, start_node_id) : execute_graph(run, graph, context)
        ensure_no_pending_joins!(graph, context)
        finalize_run(run, context)
      rescue OutputReached => e
        e.output_variables.each { |key, value| context.set_variable(key, value) }
        finalize_run(run, context)
      rescue StandardError => e
        begin
          fail_run(run, context, e)
        rescue StandardError => inner
          Rails.logger.error("[Runner] fail_run itself raised: #{inner.message}")
          # :nocov:
          run.update_columns(status: :failed, error: e.message, completed_at: Time.current) if run.active? # rubocop:disable Rails/SkipsModelValidations
          # :nocov:
        end
      end

      run.reload
    end

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

    def create_run(trigger_data:)
      mission.mission_runs.create!(
        status: :pending,
        flow_snapshot: mission.flow_data,
        trigger_data:,
      )
    end

    def allowed_run_status?(run, allowed_statuses)
      Array(allowed_statuses).map(&:to_s).include?(run.status.to_s)
    end
  end
end
