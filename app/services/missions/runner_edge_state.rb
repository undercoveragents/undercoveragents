# frozen_string_literal: true

module Missions
  # Edge-state transitions used by traversal, control-flow, and debug broadcasts.
  module RunnerEdgeState
    private

    def complete_incoming_edge(run, graph, context, incoming_edge)
      return unless incoming_edge
      return unless edge_completes_on_target_entry?(graph, incoming_edge)

      mark_edge_completed(run, context, incoming_edge)
    end

    def edge_completes_on_target_entry?(graph, edge)
      !loop_edge?(graph, edge)
    end

    def loop_edge?(graph, edge)
      ["iterator", "loop"].include?(graph.node_type(edge["source"])) && edge["sourceHandle"] == self.class::LOOP_PORT
    end

    def complete_loop_body_edges(run, graph, context, node_id)
      graph.outgoing_edges(node_id, port: self.class::LOOP_PORT).each do |edge|
        next unless context.get_edge_state(edge["id"]) == "in_progress"

        mark_edge_completed(run, context, edge)
      end
    end

    def mark_edge_in_progress(run, context, edge)
      set_edge_state(run, context, edge["id"], "in_progress")
    end

    def mark_edge_completed(run, context, edge)
      set_edge_state(run, context, edge["id"], "completed")
    end

    def mark_edge_disabled(run, context, edge)
      set_edge_state(run, context, edge["id"], "disabled")
    end

    def set_edge_state(run, context, edge_id, state)
      return if edge_id.blank?
      return if context.get_edge_state(edge_id) == state

      context.set_edge_state(edge_id, state)
      edge_state_changed(run, context, edge_id, state)
    end

    def edge_state_changed(run, context, edge_id, state); end
  end
end
