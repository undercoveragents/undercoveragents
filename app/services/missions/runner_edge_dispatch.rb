# frozen_string_literal: true

module Missions
  # Outgoing-edge resolution and queue/branch dispatch for graph traversal.
  module RunnerEdgeDispatch
    private

    def follow_edges(*args, **options)
      frame, node_id, port, options = follow_edge_args(args, options)
      strict = options.fetch(:strict, false)
      dispatch = options.fetch(:dispatch, :queue)
      edges = resolve_outgoing_edges(frame.graph, node_id, port, strict:)
      return if edges.empty?

      if dispatch == :queue && edges.size <= 1
        queue_linear_edges(frame, edges)
      else
        drain_edge_branches(frame, edges)
      end
    end

    def resolve_outgoing_edges(graph, node_id, port, strict: false)
      edges = graph.outgoing_edges(node_id, port:)

      unless strict
        edges = graph.outgoing_edges(node_id, port: "default") if edges.empty? && port != "default"
        edges = graph.outgoing_edges(node_id) if edges.empty?
      end

      edges
    end

    def queue_linear_edges(frame, edges)
      runtime_state = frame.context.snapshot_runtime_state

      edges.each do |edge|
        mark_edge_in_progress(frame.run, frame.context, edge)
        frame.scheduler.enqueue(edge["target"], incoming_edge_id: edge["id"], runtime_state:)
      end
    end

    def drain_edge_branches(frame, edges)
      if edges.size <= 1
        edges.each { |edge| drain_edge_branch(frame, edge) }
        return
      end

      execute_concurrently(edges, context: frame.context) do |edge|
        drain_edge_branch(frame, edge)
      end
    end

    def drain_edge_branch(frame, edge)
      mark_edge_in_progress(frame.run, frame.context, edge)
      branch_scheduler = frame.scheduler.fork(
        node_id: edge["target"],
        incoming_edge_id: edge["id"],
        runtime_state: frame.context.snapshot_runtime_state,
      )
      drain_scheduler(frame.run, frame.graph, frame.context, branch_scheduler)
    end
  end
end
