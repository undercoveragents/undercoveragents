# frozen_string_literal: true

module Missions
  # Graph traversal and edge-routing for mission execution.
  module RunnerTraversal
    private

    def drain_scheduler(*args)
      frame = runner_frame_from_args(args)

      while (work_item = frame.scheduler.dequeue)
        return if cancelled_run?(frame.run)

        frame.context.inherit_runtime_state(work_item.runtime_state)
        ensure_execution_capacity!(frame.scheduler.execution_count)
        process_work_item(frame, work_item)
      end
    end

    def process_work_item(frame, work_item)
      node_id = work_item.node_id
      incoming_edge = resolve_incoming_edge(frame.graph, work_item.incoming_edge_id)
      node_details = resolve_node_for_execution!(frame.graph, node_id)
      return if skip_or_defer_node_execution?(frame, node_details, incoming_edge)

      prepare_current_node_context(frame.run, frame.context, node_details)
      return if execute_special_node_flow?(frame, node_details)

      execute_regular_node_and_follow(frame, node_details)
    end

    def cancelled_run?(run)
      run.reload
      run.cancelled?
    end

    def ensure_execution_capacity!(execution_count)
      return unless execution_count.value >= self.class::MAX_TOTAL_EXECUTIONS

      raise MaxIterationsError, "Maximum total executions (#{self.class::MAX_TOTAL_EXECUTIONS}) exceeded"
    end

    def resolve_node_for_execution!(graph, node_id)
      node = graph.node(node_id)
      raise NodeNotFoundError, "Node '#{node_id}' not found in flow" unless node

      { id: node_id, type: node["type"], data: graph.node_data(node_id) }
    end

    def resolve_incoming_edge(graph, incoming_edge_id)
      return if incoming_edge_id.blank?

      graph.edge(incoming_edge_id) || raise(ExecutionError, "Edge '#{incoming_edge_id}' not found in flow")
    end

    def skip_or_defer_node_execution?(*args)
      frame, node_details, incoming_edge = skip_node_args(args)

      if node_details[:data]["disabled"]
        skip_disabled_node(frame, node_details[:id], node_details[:type])
        return true
      end

      if runtime_node_disabled?(frame.context, node_details[:id])
        frame.scheduler.complete_active_work_item
        return true
      end

      complete_incoming_edge(frame.run, frame.graph, frame.context, incoming_edge)
      join_waiting = !node_ready_to_execute?(frame.run, frame.graph, frame.context, node_details[:id], incoming_edge)
      frame.scheduler.complete_active_work_item if join_waiting
      join_waiting
    end

    def execute_regular_node_and_follow(frame, node_details)
      result = execute_regular_node(frame, node_details)
      execution_state = { node_details:, next_port: result.next_port }
      prune_completed_node_branches(frame, execution_state)
      follow_regular_node_edges(frame, execution_state)
    end

    def execute_regular_node(frame, node_details)
      execute_single_node(NodeExecutionRequest.from_frame(frame, node_details))
    end

    def prune_completed_node_branches(frame, execution_state)
      prune_unselected_branches!(frame, execution_state[:next_port])
      frame.context.clear_node_arrivals(execution_state.dig(:node_details, :id))
    end

    def follow_regular_node_edges(frame, execution_state)
      node_details = execution_state[:node_details]

      follow_edges(
        frame,
        node_details[:id],
        execution_state[:next_port],
        strict: multi_port_node?(node_details[:type]),
      )
    end
  end
end
