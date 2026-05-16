# frozen_string_literal: true

module Missions
  # Multi-input join readiness, arrival tracking, and unresolved barrier diagnostics.
  module RunnerJoinSynchronization
    private

    def node_ready_to_execute?(run, graph, context, node_id, incoming_edge)
      expected_predecessor_ids = active_join_predecessor_ids(graph, context, node_id)
      return true if expected_predecessor_ids.size <= 1

      record_node_arrival(graph, context, node_id, incoming_edge)

      missing_predecessor_ids = expected_predecessor_ids - context.node_arrivals_for(node_id)
      return true if missing_predecessor_ids.empty?

      persist_state(run, context, current_node_id: node_id)
      false
    end

    def ensure_no_pending_joins!(graph, context)
      pending = pending_join_barriers(graph, context)

      return if pending.empty?

      details = pending.map do |join|
        "\"#{join[:label]}\" (#{join[:node_id]}) is waiting for " \
          "#{join[:missing_count]} of #{join[:expected_count]} required predecessor signals"
      end

      message = [
        "Unresolved multi-input join: #{details.join("; ")}.",
        "Any node with multiple active incoming predecessors waits for each unique immediate predecessor node.",
        "Multiple direct ports from the same upstream node count as one signal " \
        "while any of those edges remain enabled.",
        "Disabled edges do not block downstream joins.",
      ].join(" ")

      raise ExecutionError, message
    end

    def pending_join_barriers(graph, context)
      context.node_arrivals.each_with_object([]) do |(node_id, arrived_predecessor_ids), result|
        pending = build_pending_join_barrier(graph, context, node_id, arrived_predecessor_ids)
        result << pending if pending
      end
    end

    def build_pending_join_barrier(graph, context, node_id, arrived_predecessor_ids)
      expected_predecessor_ids = active_join_predecessor_ids(graph, context, node_id)
      return if expected_predecessor_ids.size <= 1

      missing_predecessor_ids = expected_predecessor_ids - Array(arrived_predecessor_ids).map(&:to_s)
      return if missing_predecessor_ids.empty?

      {
        node_id:,
        label: join_barrier_label(graph, node_id),
        missing_count: missing_predecessor_ids.size,
        expected_count: expected_predecessor_ids.size,
      }
    end

    def record_node_arrival(graph, context, node_id, incoming_edge)
      predecessor_id = join_predecessor_id(graph, incoming_edge)
      context.record_node_arrival(node_id, predecessor_id) if predecessor_id.present?
    end

    def join_predecessor_id(graph, incoming_edge)
      return if incoming_edge.blank?

      incoming_edge["source"].presence || graph.edge(incoming_edge["id"])&.dig("source")
    end

    def join_barrier_label(graph, node_id)
      data = graph.node_data(node_id)
      data["label"].presence || data["name"].presence || node_id
    end
  end
end
