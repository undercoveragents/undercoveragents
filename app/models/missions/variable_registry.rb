# frozen_string_literal: true

module Missions
  # Design-time registry that computes which variables are available at any
  # point in a mission flow.  Uses topological traversal of a +FlowGraph+ to
  # collect each upstream node's declared +variable_schema+ outputs.
  #
  # Variables are always scoped: +node_prefix.variable_name+ (e.g.
  # +summarizer.response+). Prefixes are resolved uniquely per flow, so later
  # duplicate labels receive numeric suffixes such as +json_extract_2+.
  #
  # Port-aware: nodes with multiple output handles (iterator, loop, condition,
  # switch) declare which variables are produced on each port.  Only variables
  # matching the handle that reaches the target node are included.
  class VariableRegistry
    Entry = Data.define(:name, :type, :description, :node_id, :node_name, :qualified_name) do
      def initialize(name:, type: :any, description: "", node_id: nil, node_name: nil, qualified_name: nil)
        super
      end
    end

    # Built-in variables available in every execution context.
    BUILTIN_VARIABLES = [
      Entry.new(name: "input", type: :string, description: "Initial input passed to the mission"),
    ].freeze

    attr_reader :graph

    def initialize(flow_data)
      @flow_data = Missions::FlowDataSanitizer.sanitize(flow_data)
      @graph = FlowGraph.new(@flow_data)
      @node_names = Missions::NodeVariableNameResolver.build_map(@flow_data)
    end

    # Returns all variable entries available *before* the given node executes.
    # Port-aware: only includes outputs matching the handle that reaches this
    # node from each predecessor.
    def available_at(node_id)
      order = sorted_ids
      idx = order.index(node_id)
      return BUILTIN_VARIABLES.dup + global_variable_entries unless idx

      predecessors, port_map = reachable_predecessors_with_ports(node_id)
      ordered = order.first(idx).select { |id| predecessors.include?(id) }
      entries = BUILTIN_VARIABLES.dup + global_variable_entries

      ordered.each do |uid|
        active_ports = port_map[uid]
        entries.concat(outputs_for_node(uid, active_ports:))
      end

      entries
    end

    # Returns all variable entries produced by every node in the flow.
    def all_variables
      entries = BUILTIN_VARIABLES.dup + global_variable_entries

      sorted_ids.each do |nid|
        entries.concat(outputs_for_node(nid))
      end

      entries
    end

    # Returns the output variable entries declared by a single node.
    # When +active_ports+ is given, only variables matching those ports
    # (or port-less variables) are included.
    def outputs_for_node(node_id, active_ports: nil)
      node = @graph.node(node_id)
      return [] unless node

      node_data = @graph.node_data(node_id)
      node_name = derive_node_name(node_data, node_id)
      klass = MissionNodePlugin.resolve(node["type"])
      return [] unless klass

      entries = []
      entries.concat(build_entries(klass, node_id, node_name, node_data, active_ports))

      entries
    end

    private

    # Topological sort, silently falling back to node_ids on cycles.
    def sorted_ids
      @graph.topological_sort
    rescue CyclicGraphError
      @graph.node_ids
    end

    # BFS backwards to find all transitive predecessors of a node, recording
    # which output port (sourceHandle) of each predecessor is on the path
    # toward the target.
    #
    # Returns [Set<predecessor_ids>, Hash<predecessor_id => Set<port>>].
    def reachable_predecessors_with_ports(node_id)
      visited = Set.new
      port_map = Hash.new { |h, k| h[k] = Set.new }
      queue = [node_id]
      bfs_incoming(visited, port_map, queue)

      [visited, port_map]
    end

    def bfs_incoming(visited, port_map, queue)
      until queue.empty?
        current = queue.shift
        @graph.incoming_edges(current).each do |edge|
          source = edge["source"]
          port_map[source].add(edge["sourceHandle"])

          unless visited.include?(source)
            visited.add(source)
            queue << source
          end
        end
      end
    end

    # Builds Entry objects for each global variable defined in flow_data.
    # Global variables are available everywhere — no graph traversal needed.
    def global_variable_entries
      (@flow_data["global_variables"] || []).filter_map do |var|
        next if var["key"].blank?

        type = case var["type"]
               when "number" then :number
               when "boolean" then :boolean
               else :string
               end

        Entry.new(
          name: var["key"],
          type:,
          description: "Global variable",
          node_id: nil,
          node_name: nil,
          qualified_name: var["key"],
        )
      end
    end

    def derive_node_name(node_data, node_id)
      @node_names[node_id.to_s] || Missions::NodeVariableNameResolver.base_name(node_data, node_id)
    end

    def build_entries(klass, node_id, node_name, node_data, active_ports = nil)
      entries = []
      schema = klass.variable_schema

      schema.outputs.each do |var|
        if var.name == "*"
          entries.concat(dynamic_output_entries(klass, node_id, node_name, node_data))
          next
        end

        # Port filtering: skip if the variable belongs to a specific port
        # that is not in the set of ports leading to the target.
        next if var.port && active_ports && active_ports.exclude?(var.port)

        entries << Entry.new(
          name: var.name,
          type: var.type,
          description: var.description,
          node_id:,
          node_name:,
          qualified_name: "#{node_name}.#{var.name}",
        )
      end

      entries
    end

    def dynamic_output_entries(klass, node_id, node_name, node_data)
      klass.dynamic_output_variables(node_data).filter_map do |output|
        name = output[:name].to_s
        next if name.blank?

        Entry.new(
          name:,
          type: output.fetch(:type, :any),
          description: output.fetch(:description, ""),
          node_id:,
          node_name:,
          qualified_name: "#{node_name}.#{name}",
        )
      end
    end
  end
end
