# frozen_string_literal: true

module Missions
  # Immutable directed graph built from a mission's flow_data JSON.
  # Provides fast lookups for traversal, topological analysis, and validation.
  class FlowGraph
    VALID_GRAPH = true

    attr_reader :nodes, :edges

    def initialize(flow_data)
      raw_flow = Missions::FlowDataSanitizer.sanitize(flow_data)
      raw_nodes = raw_flow["nodes"]
      raw_edges = raw_flow["edges"]

      @nodes = raw_nodes.to_h do |n|
        [n["id"], n.freeze]
      end.freeze

      @edges = raw_edges.map(&:freeze).freeze

      build_adjacency!
    end

    # ── Node lookups ──

    def node(id)
      @nodes[id]
    end

    def node_type(id)
      @nodes.dig(id, "type")
    end

    def node_data(id)
      @nodes.dig(id, "data") || {}
    end

    def node_ids
      @nodes.keys
    end

    def edge(id)
      @edges_by_id[id.to_s]
    end

    # ── Edge traversal ──

    # Returns all nodes directly reachable from a given node.
    # If port is specified, only follows edges from that source handle.
    def successors(node_id, port: nil)
      edges = @outgoing[node_id] || []
      edges = edges.select { |e| e["sourceHandle"] == port } if port
      edges.pluck("target").compact.uniq
    end

    # Returns all nodes that connect into a given node.
    def predecessors(node_id)
      edges = @incoming[node_id] || []
      edges.pluck("source").compact.uniq
    end

    # Returns incoming edge objects for a node (includes sourceHandle metadata).
    def incoming_edges(node_id)
      @incoming[node_id] || []
    end

    # Returns outgoing edges from a node, optionally filtered by sourceHandle.
    def outgoing_edges(node_id, port: nil)
      edges = @outgoing[node_id] || []
      return edges unless port

      edges.select { |e| e["sourceHandle"] == port }
    end

    # ── Graph queries ──

    # Finds all trigger / input nodes (entry points).
    def trigger_nodes
      @nodes.values.select do |n|
        category_for(n).in?(["trigger", "input_output"]) &&
          n["type"] != "output"
      end
    end

    # Finds all output nodes (terminal points).
    def output_nodes
      @nodes.values.select { |n| category_for(n).in?(["output", "input_output"]) && n["type"] == "output" }
    end

    # Finds nodes with no incoming edges (roots).
    def root_nodes
      @nodes.values.select { |n| (@incoming[n["id"]] || []).empty? }
    end

    # Finds nodes with no outgoing edges (leaves).
    def leaf_nodes
      @nodes.values.select { |n| (@outgoing[n["id"]] || []).empty? }
    end

    # Topological sort. Raises CyclicGraphError if cycle detected.
    def topological_sort
      in_degree = @nodes.each_key.index_with { |id| predecessors(id).size }

      queue = @nodes.keys.select { |id| in_degree[id].zero? }
      sorted = []

      until queue.empty?
        id = queue.shift
        sorted << id
        successors(id).each do |target|
          next unless in_degree.key?(target)

          in_degree[target] -= 1
          queue << target if in_degree[target].zero?
        end
      end

      raise CyclicGraphError, "Flow contains a cycle" if sorted.size != @nodes.size

      sorted
    end

    # Validates the graph structure.
    def validate!
      errors = []
      errors << "No nodes defined" if @nodes.empty?
      if trigger_nodes.empty? && root_nodes.empty?
        errors << "No entry point found (add a trigger node or a node with no incoming connections)"
      end

      @edges.each { |edge| validate_edge!(edge, errors) }

      raise InvalidFlowError, errors.join("; ") if errors.any?

      VALID_GRAPH
    end

    private

    def build_adjacency!
      @outgoing = Hash.new { |h, k| h[k] = [] }
      @incoming = Hash.new { |h, k| h[k] = [] }
      @edges_by_id = {}

      @edges.each do |edge|
        @outgoing[edge["source"]] << edge
        @incoming[edge["target"]] << edge
        @edges_by_id[edge["id"].to_s] = edge if edge["id"].present?
      end

      @edges_by_id.freeze
    end

    def category_for(node)
      type = node["type"]
      MissionNodePlugin.category_for(type) || infer_category(type)
    end

    def infer_category(type)
      return "input_output" if type.to_s.in?(["input", "output"])
      return "trigger" if type.to_s.include?("trigger")
      return "output" if type.to_s.include?("output")
      return "control" if ["condition", "switch", "iterator", "loop"].include?(type.to_s)

      "node"
    end

    def validate_edge!(edge, errors)
      source_id = edge["source"]
      target_id = edge["target"]

      errors << "Edge references missing source node '#{source_id}'" unless @nodes.key?(source_id)
      errors << "Edge references missing target node '#{target_id}'" unless @nodes.key?(target_id)
    end
  end
end
