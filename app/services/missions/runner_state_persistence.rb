# frozen_string_literal: true

module Missions
  # Run-state persistence, current-node updates, and active-frontier checkpoints.
  module RunnerStatePersistence
    private

    def prepare_current_node_context(run, context, node_details)
      run.with_lock { run.update!(current_node_id: node_details[:id]) }
      context.set_variable("_current_node_id", node_details[:id])
      context.set_variable("_current_node_type", node_details[:type])
      context.set_variable("_current_node_data", node_details[:data])
    end

    def checkpoint_active_frontier(run, context, node_id, scheduler)
      scheduler.refresh_active_work_item(runtime_state: context.snapshot_runtime_state)
      persist_state(run, context, current_node_id: node_id)
    end

    def finalize_run(run, context)
      run.reload
      unless run.active?
        persist_cancelled_run_state(run, context)
        return
      end

      write_run_state(
        run,
        context,
        status: :completed,
        completed_at: Time.current,
        current_node_id: nil,
      )
    end

    def fail_run(run, context, error)
      persist_failure_node_state(run, context, error)

      write_run_state(
        run,
        context,
        status: :failed,
        error: error.message,
        completed_at: Time.current,
        current_node_id: nil,
      )
    end

    def persist_state(run, context, current_node_id: nil)
      write_run_state(run, context, current_node_id:)
    end

    def persist_cancelled_run_state(run, context)
      write_run_state(run, context, current_node_id: nil) if run.cancelled?
    end

    def write_run_state(run, context, **attrs)
      run.with_lock do
        run.update!(
          variables: context.variables,
          execution_state: context.to_h,
          **attrs,
        )
      end
    end

    def persist_failure_node_state(run, context, error)
      node_id = failure_node_id(run, context)
      return if node_id.blank?

      context.set_node_state(
        node_id,
        :failure,
        node_type: failure_node_type(run, context, node_id),
        error: error.message,
      )
    end

    def failure_node_id(run, context)
      run.current_node_id.presence || context.get_variable("_current_node_id").presence
    end

    def failure_node_type(run, context, node_id)
      context.get_variable("_current_node_type").presence ||
        (run.flow_snapshot["nodes"] || []).find { |node| node["id"] == node_id }.to_h["type"]
    end
  end
end
