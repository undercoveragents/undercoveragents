# frozen_string_literal: true

module Missions
  # Validates iterator/loop body boundaries so per-iteration subgraphs do not
  # reconnect into their own control node or mix body inputs with outside inputs.
  class LoopBodyBoundaryValidator
    Error = Data.define(:node_id, :field, :message)

    LOOPING_NODE_TYPES = ["iterator", "loop"].freeze
    LOOP_PORT = "loop"
    CANDIDATE_EDGE_ID = "__candidate_loop_body_edge__"

    def self.errors_for(flow_data)
      new(flow_data).errors
    end

    def self.error_for_candidate_edge(flow_data:, source_node_id:, target_node_id:, source_port: LOOP_PORT)
      new(
        flow_data,
        candidate_edge: {
          "id" => CANDIDATE_EDGE_ID,
          "source" => source_node_id,
          "sourceHandle" => source_port,
          "target" => target_node_id,
        },
      ).candidate_error
    end

    def initialize(flow_data, candidate_edge: nil)
      @candidate_edge = candidate_edge
      @graph = FlowGraph.new(build_flow(flow_data, candidate_edge))
      @body_cache = {}
      @errors = []
      @seen_errors = Set.new
    end

    def errors
      control_node_ids.each do |control_id|
        body_node_ids = loop_body_node_ids(control_id)
        next if body_node_ids.empty?

        validate_control_reentry(control_id, body_node_ids)
        validate_mixed_boundary_inputs(control_id, body_node_ids)
      end

      @errors
    end

    def candidate_error
      return if @candidate_edge.blank?

      control_node_ids.each do |control_id|
        body_node_ids = loop_body_node_ids(control_id)
        next if body_node_ids.empty?

        error_message = candidate_control_reentry_error(control_id, body_node_ids)
        return error_message if error_message

        error_message = candidate_mixed_boundary_error(control_id, body_node_ids)
        return error_message if error_message
      end

      nil
    end

    private

    def build_flow(flow_data, candidate_edge)
      flow = Missions::FlowDataSanitizer.sanitize(flow_data.deep_dup)
      flow["nodes"] ||= []
      flow["edges"] ||= []
      flow["edges"] << candidate_edge if candidate_edge.present?
      flow
    end

    def control_node_ids
      @graph.node_ids.select { |node_id| LOOPING_NODE_TYPES.include?(@graph.node_type(node_id).to_s) }
    end

    def loop_body_node_ids(control_id)
      @body_cache[control_id] ||= begin
        visited = Set.new
        queue = loop_body_seed_targets(control_id)

        visit_loop_body_nodes(control_id, queue, visited)

        visited
      end
    end

    def validate_control_reentry(control_id, body_node_ids)
      @graph.incoming_edges(control_id).each do |edge|
        next unless body_node_ids.include?(edge["source"].to_s)

        add_error(control_id, reentry_message(control_id))
      end
    end

    def validate_mixed_boundary_inputs(control_id, body_node_ids)
      body_node_ids.each do |node_id|
        incoming_edges = @graph.incoming_edges(node_id)
        next if incoming_edges.empty?

        has_inside_input = incoming_edges.any? { |edge| inside_body_edge?(control_id, body_node_ids, edge) }
        has_outside_input = incoming_edges.any? { |edge| outside_body_edge?(control_id, body_node_ids, edge) }
        next unless has_inside_input && has_outside_input

        add_error(node_id, mixed_boundary_message(control_id, node_id))
      end
    end

    def candidate_control_reentry_error(control_id, body_node_ids)
      return unless candidate_edge_targets?(control_id)
      return unless body_node_ids.include?(candidate_edge_source_id)

      reentry_message(control_id)
    end

    def candidate_mixed_boundary_error(control_id, body_node_ids)
      return unless body_node_ids.include?(candidate_edge_target_id)

      return unless candidate_creates_mixed_boundary?(control_id, body_node_ids)

      mixed_boundary_message(control_id, candidate_edge_target_id)
    end

    def candidate_edge_source_id
      @candidate_edge["source"].to_s
    end

    def candidate_edge_target_id
      @candidate_edge["target"].to_s
    end

    def candidate_edge_targets?(node_id)
      candidate_edge_target_id == node_id.to_s
    end

    def inside_body_edge?(control_id, body_node_ids, edge)
      source_id = edge["source"].to_s
      return false if source_id.blank?

      if source_id == control_id.to_s
        edge["sourceHandle"].presence == LOOP_PORT
      else
        body_node_ids.include?(source_id)
      end
    end

    def outside_body_edge?(control_id, body_node_ids, edge)
      !inside_body_edge?(control_id, body_node_ids, edge)
    end

    def loop_body_seed_targets(control_id)
      @graph.outgoing_edges(control_id, port: LOOP_PORT).filter_map { |edge| edge["target"].presence }
    end

    def visit_loop_body_nodes(control_id, queue, visited)
      until queue.empty?
        node_id = queue.shift
        next unless visitable_loop_body_node?(node_id, control_id, visited)

        visited.add(node_id)
        enqueue_loop_body_targets(node_id, control_id, visited, queue)
      end
    end

    def visitable_loop_body_node?(node_id, control_id, visited)
      node_id.present? && node_id != control_id && visited.exclude?(node_id)
    end

    def enqueue_loop_body_targets(node_id, control_id, visited, queue)
      @graph.outgoing_edges(node_id).filter_map { |edge| edge["target"].presence }.each do |target_id|
        queue << target_id if visitable_loop_body_node?(target_id, control_id, visited)
      end
    end

    def candidate_creates_mixed_boundary?(control_id, body_node_ids)
      other_edges = incoming_edges_without_candidate(candidate_edge_target_id)
      return false if other_edges.empty?

      candidate_inside = inside_body_edge?(control_id, body_node_ids, @candidate_edge)
      other_inside, other_outside = boundary_presence(control_id, body_node_ids, other_edges)

      (candidate_inside && other_outside) || (!candidate_inside && other_inside)
    end

    def incoming_edges_without_candidate(node_id)
      @graph.incoming_edges(node_id).reject { |edge| edge["id"].to_s == CANDIDATE_EDGE_ID }
    end

    def boundary_presence(control_id, body_node_ids, edges)
      [
        edges.any? { |edge| inside_body_edge?(control_id, body_node_ids, edge) },
        edges.any? { |edge| outside_body_edge?(control_id, body_node_ids, edge) },
      ]
    end

    def reentry_message(control_id)
      control_kind = @graph.node_type(control_id).to_s.humanize(capitalize: false)
      control_label = node_label(control_id)

      "#{control_kind.capitalize} \"#{control_label}\" cannot receive an incoming edge from its own body. " \
        "#{control_kind.capitalize} nodes re-evaluate internally; do not wire body nodes back into the control node."
    end

    def mixed_boundary_message(control_id, node_id)
      control_label = node_label(control_id)
      node_label = node_label(node_id)

      "Node \"#{node_label}\" mixes inputs from inside and outside loop/iterator body \"#{control_label}\". " \
        "Nodes inside a loop or iterator body cannot join with outside predecessors; route once-per-run work " \
        "through the control node done port instead."
    end

    def node_label(node_id)
      data = @graph.node_data(node_id)
      data["label"].presence || data["name"].presence || node_id.to_s
    end

    def add_error(node_id, message)
      key = [node_id.to_s, message]
      return unless @seen_errors.add?(key)

      @errors << Error.new(node_id.to_s, "edges", message)
    end
  end
end
