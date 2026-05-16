# frozen_string_literal: true

module Missions
  module RunnerBranchPruning
    private

    def prune_unselected_branches!(frame, selected_port)
      node_id = frame.context.get_variable("_current_node_id").to_s
      node_type = frame.context.get_variable("_current_node_type").to_s
      return unless mutually_exclusive_output_node?(node_type)

      restore_branch_states!(frame.graph, frame.context, node_id)
      disable_unselected_edges!(frame, selected_port)
      persist_state(frame.run, frame.context, current_node_id: node_id)
    end

    def disable_unselected_edges!(frame, selected_port)
      node_id = frame.context.get_variable("_current_node_id").to_s
      disabled_edges = frame.graph.outgoing_edges(node_id).reject do |edge|
        normalize_branch_port(edge["sourceHandle"]) == normalize_branch_port(selected_port)
      end
      return if disabled_edges.empty?

      visited_edges = Set.new
      visited_nodes = Set.new

      disabled_edges.each do |edge|
        disable_edge_branch!(frame, edge, visited_edges:, visited_nodes:)
      end
    end

    def restore_branch_states!(graph, context, node_id)
      visited_edges = Set.new
      visited_nodes = Set.new

      graph.outgoing_edges(node_id).each do |edge|
        restore_edge_branch!(
          graph,
          context,
          edge,
          visited_edges:,
          visited_nodes:,
        )
      end
    end

    def active_join_predecessor_ids(graph, context, node_id)
      graph.incoming_edges(node_id).each_with_object(Set.new) do |edge, predecessor_ids|
        next if edge_disabled?(context, edge)

        predecessor_ids << edge["source"].to_s
      end.to_a
    end

    def runtime_node_disabled?(context, node_id)
      context.get_node_state(node_id).to_h["status"] == "disabled"
    end

    def node_state_changed(_run, _context, _node_id, _state, node_type: nil); end

    def disable_edge_branch!(*args, visited_edges:, visited_nodes:)
      frame, edge = branch_edge_args(args)
      return if edge.blank?

      edge_id = edge["id"].to_s
      return if edge_id.blank? || visited_edges.include?(edge_id)

      visited_edges.add(edge_id)
      mark_edge_disabled(frame.run, frame.context, edge)

      target_id = edge["target"].to_s
      return if target_id.blank?

      if node_has_enabled_incoming_edges?(frame.graph, frame.context, target_id)
        wake_join_if_unblocked!(frame.graph, frame.context, target_id, frame.scheduler)
        return
      end

      disable_node_branch!(frame, target_id, visited_edges:, visited_nodes:)
    end

    def restore_edge_branch!(graph, context, edge, visited_edges:, visited_nodes:)
      edge_id = edge["id"].to_s
      return if skip_restoring_edge?(edge, edge_id, visited_edges)

      visited_edges.add(edge_id)
      context.clear_edge_state(edge_id)

      target_id = edge["target"].to_s
      return if target_id.blank?

      restore_target_node_state(graph, context, target_id)
      restore_downstream_edges(graph, context, target_id, visited_edges:, visited_nodes:)
    end

    def skip_restoring_edge?(edge, edge_id, visited_edges)
      edge.blank? || edge_id.blank? || visited_edges.include?(edge_id)
    end

    def restore_target_node_state(graph, context, target_id)
      return unless node_has_enabled_incoming_edges?(graph, context, target_id)

      context.clear_node_state(target_id)
    end

    def restore_downstream_edges(graph, context, target_id, visited_edges:, visited_nodes:)
      return unless visited_nodes.add?(target_id)

      graph.outgoing_edges(target_id).each do |outgoing_edge|
        restore_edge_branch!(
          graph,
          context,
          outgoing_edge,
          visited_edges:,
          visited_nodes:,
        )
      end
    end

    def disable_node_branch!(*args, visited_edges:, visited_nodes:)
      frame, node_id = branch_node_args(args)
      return if node_id.blank? || visited_nodes.include?(node_id)

      visited_nodes.add(node_id)

      node = frame.graph.node(node_id)
      return unless node

      node_type = node["type"].to_s
      set_runtime_node_state(frame.run, frame.context, node_id, "disabled", node_type:)
      frame.context.clear_node_arrivals(node_id)

      frame.graph.outgoing_edges(node_id).each do |outgoing_edge|
        disable_edge_branch!(frame, outgoing_edge, visited_edges:, visited_nodes:)
      end
    end

    def set_runtime_node_state(run, context, node_id, state, node_type: nil)
      current = context.get_node_state(node_id).to_h
      return if current["status"] == state.to_s && current["node_type"] == node_type.to_s

      context.set_node_state(node_id, state, node_type:)
      node_state_changed(run, context, node_id, state, node_type:)
    end

    def wake_join_if_unblocked!(graph, context, node_id, scheduler)
      return if runtime_node_disabled?(context, node_id)

      arrived_predecessor_ids = context.node_arrivals_for(node_id)
      return if arrived_predecessor_ids.empty?

      active_predecessor_ids = active_join_predecessor_ids(graph, context, node_id)
      return if active_predecessor_ids.empty?
      return unless (active_predecessor_ids - arrived_predecessor_ids).empty?

      scheduler.enqueue(node_id, runtime_state: context.snapshot_runtime_state)
    end

    def node_has_enabled_incoming_edges?(graph, context, node_id)
      graph.incoming_edges(node_id).any? { |incoming_edge| !edge_disabled?(context, incoming_edge) }
    end

    def edge_disabled?(context, edge)
      context.get_edge_state(edge["id"]) == "disabled"
    end

    def mutually_exclusive_output_node?(node_type)
      MissionNodePlugin.resolve(node_type)&.mutually_exclusive_output_ports? == true
    end

    def normalize_branch_port(port)
      port.presence || "default"
    end
  end
end
