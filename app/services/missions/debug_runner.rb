# frozen_string_literal: true

require "English"

module Missions
  # A runner that broadcasts real-time execution events via Turbo Streams
  # so the designer can visualize step-by-step execution.
  #
  # Broadcasts:
  #   - Timeline entries (appended to the timeline list)
  #   - Variable snapshots (replaced in the variables tab)
  #   - Run status updates (replaced in the status indicator + controls)
  #   - Node state events (appended as hidden data elements for Stimulus → React bridge)
  class DebugRunner < Runner
    include DebugRunnerBroadcasts
    include DebugRunnerBroadcastArgs
    include DebugRunnerOutputSanitizer
    include DebugRunnerStatusBroadcasts

    STREAM_PREFIX = "mission_debug"
    # Keep live debug snapshots comfortably below PostgreSQL's 8 KB NOTIFY
    # limit even when several variables and node outputs are rendered together.
    BROADCAST_STRING_LIMIT = 240
    BROADCAST_ARRAY_LIMIT = 10
    BROADCAST_HASH_LIMIT = 12
    BROADCAST_DEPTH_LIMIT = 4
    BROADCAST_HASH_NOTICE_KEY = "__truncated__"
    BROADCAST_NESTED_NOTICE = "... (nested data truncated)"

    private

    def execute_run(run, variables: {}, trigger_data: {})
      begin
        validate_global_variables!(run)
      rescue ExecutionError => e
        run.update!(status: :failed, error: e.message, completed_at: Time.current)
        safely_broadcast { broadcast_run_status(run, "failed") }
        return run.reload
      end

      @node_completion_counts = Hash.new(0)
      @iterator_started_ats = {}
      @loop_started_ats = {}
      @running_node_ids = Set.new
      # Brief pause to let the client establish its Turbo Stream subscription
      # before any broadcasts begin (avoids losing early events like the
      # "running" status or first node states).
      sleep(0.5)
      safely_broadcast { broadcast_run_status(run, "running") }
      # Broadcast a reset for every edge so any stale state from a previous run
      # (e.g. from a JS race between catch-up fetch and the new run starting)
      # is wiped before new traversal events arrive.
      broadcast_all_edges_reset(run)
      super
    end

    def execute_single_node(request)
      mark_debug_node_running(request)

      result = super

      return result if broadcast_cancelled_node_completion?(request)

      broadcast_successful_node_completion(request, result)
      result
    rescue Missions::OutputReached
      broadcast_output_reached_node(request)
      raise
    rescue Missions::ExecutionError
      broadcast_failed_node(request, $ERROR_INFO.message)
      raise
    rescue StandardError => e
      broadcast_failed_node(request, e.message)
      raise
    end

    def mark_debug_node_running(request)
      @running_node_ids.add(request.node_id)
      safely_broadcast do
        broadcast_node_state(
          request.run,
          request.node_id,
          request.node_type,
          "running",
          completed_count: @node_completion_counts[request.node_id],
        )
      end
    end

    def broadcast_cancelled_node_completion?(request)
      @running_node_ids.delete(request.node_id)
      return false unless request.run.reload.cancelled?

      safely_broadcast { broadcast_node_state(request.run, request.node_id, request.node_type, "cancelled") }
      safely_broadcast { broadcast_cancelled_timeline_entry(request.run, request.node_id) }
      broadcast_remaining_cancelled(request.run, request.node_id)
      safely_broadcast { broadcast_run_status(request.run, "cancelled") }
      true
    end

    def broadcast_successful_node_completion(request, result)
      @node_completion_counts[request.node_id] += 1
      node_label = request.node_data["label"].presence || request.node_data["name"].presence
      safely_broadcast { broadcast_node_completed(request.run, request, result, node_label) }
      safely_broadcast { broadcast_variables(request.run, request.context) }
    end

    def broadcast_output_reached_node(request)
      @running_node_ids.delete(request.node_id)
      @node_completion_counts[request.node_id] += 1
      safely_broadcast { broadcast_node_state(request.run, request.node_id, request.node_type, "success") }
      broadcast_remaining_cancelled(request.run, request.node_id)
    end

    def broadcast_failed_node(request, message)
      @running_node_ids.delete(request.node_id)
      safely_broadcast do
        broadcast_node_state(request.run, request.node_id, request.node_type, "failure", error: message)
      end
    end

    def execute_iterator_flow(frame, node_id, node_data)
      execute_control_node_flow_with_broadcasts(frame.run, node_id, "iterator", @iterator_started_ats) { super }
    end

    def on_iterator_loop_done(run, graph, context, node_id)
      broadcast_control_node_done(run, context, node_id, "iterator", @iterator_started_ats)
      super
    end

    def execute_loop_flow(frame, node_id, node_data)
      execute_control_node_flow_with_broadcasts(frame.run, node_id, "loop", @loop_started_ats) { super }
    end

    def on_loop_done(run, graph, context, node_id)
      broadcast_control_node_done(run, context, node_id, "loop", @loop_started_ats)
      super
    end

    def finalize_run(run, context)
      super
      safely_broadcast { broadcast_run_status(run, "completed") } if run.completed?
    end

    def fail_run(run, context, error)
      super
      safely_broadcast { broadcast_run_status(run, "failed", error: error.message) }
    end

    # Checks that every global variable in the flow snapshot has a non-blank value.
    # Raises ExecutionError listing all missing keys so the debug panel shows
    # a clear error before any nodes execute.
    def validate_global_variables!(run)
      globals = run.flow_snapshot["global_variables"] || []
      missing = globals.select { |v| v["value"].blank? }.pluck("key")
      return if missing.empty?

      raise ExecutionError,
            "Global variables missing values: #{missing.join(", ")}. " \
            "Set values in the Variables panel before running."
    end
  end
end
