# frozen_string_literal: true

module Missions
  # Validates a mission flow and returns structured results.
  # Checks configuration errors, structural issues, and warnings.
  #
  # Usage:
  #   result = Missions::FlowValidator.call(mission)
  #   result.valid?            # => true/false
  #   result.config_errors     # => { "node-1" => [{ node_name:, node_type:, field:, message: }] }
  #   result.structural_issues # => ["Node X is disconnected..."]
  #   result.warnings          # => ["Node Y has unconnected ports..."]
  class FlowValidator
    Result = Data.define(:config_errors, :structural_issues, :warnings, :node_count, :edge_count) do
      def valid?
        config_errors.empty? && structural_issues.empty?
      end
    end

    TERMINAL_TYPES = ["output"].freeze
    LOOPING_NODE_TYPES = ["iterator", "loop"].freeze

    def self.call(mission)
      new(mission).call
    end

    def initialize(mission)
      @mission = mission
    end

    def call
      flow = Missions::FlowDataSanitizer.sanitize(@mission.flow_data)
      nodes = parse_nodes(flow)
      edges = parse_edges(flow)

      Result.new(
        config_errors: build_config_errors(flow, nodes),
        structural_issues: check_structure(nodes, edges),
        warnings: check_warnings(nodes, edges, flow),
        node_count: nodes.size,
        edge_count: edges.size,
      )
    end

    private

    def parse_nodes(flow)
      (flow["nodes"] || []).map do |n|
        {
          id: n["id"],
          name: n.dig("data", "label") || n["type"],
          type: n["type"],
          data: n["data"] || {},
        }
      end
    end

    def parse_edges(flow)
      (flow["edges"] || []).map do |e|
        { id: e["id"], source: e["source"], target: e["target"], source_port: e["sourceHandle"] }
      end
    end

    def build_config_errors(flow, nodes)
      raw_errors = NodeConfigValidator.validate_flow(flow)
      raw_errors.each_with_object({}) do |(node_id, errs), result|
        node = nodes.find { |n| n[:id] == node_id }
        result[node_id] = errs.map do |err|
          { node_name: node&.dig(:name), node_type: node&.dig(:type), field: err[:field], message: err[:message] }
        end
      end
    end

    def check_structure(nodes, edges)
      issues = []
      return issues if nodes.empty?

      source_ids = edges.to_set { |e| e[:source] }
      target_ids = edges.to_set { |e| e[:target] }
      node_ids = nodes.to_set { |n| n[:id] }
      edge_context = build_edge_validation_context(nodes)

      check_orphaned_nodes(nodes, source_ids, target_ids, issues)
      check_missing_outgoing(nodes, edges, source_ids, issues)
      check_dangling_edges(edges, node_ids, issues)
      check_invalid_edge_ports(edges, issues, edge_context)

      issues
    end

    def check_orphaned_nodes(nodes, source_ids, target_ids, issues)
      return if nodes.size <= 1

      nodes.each do |node|
        next if target_ids.include?(node[:id]) || source_ids.include?(node[:id])

        issues << "Node \"#{node[:name]}\" (#{node[:id]}) is disconnected from the flow"
      end
    end

    def check_missing_outgoing(nodes, edges, source_ids, issues)
      return if nodes.size <= 1

      missing_outgoing_context = build_missing_outgoing_context(nodes, edges)

      nodes.each do |node|
        next unless missing_outgoing?(node, source_ids, missing_outgoing_context)

        issues << "Node \"#{node[:name]}\" (#{node[:id]}, type: #{node[:type]}) has no outgoing connections"
      end
    end

    def build_missing_outgoing_context(nodes, edges)
      {
        node_map: nodes.index_by { |node| node[:id] },
        edges_by_target: edges.group_by { |edge| edge[:target] },
        loop_body_cache: {},
      }
    end

    def missing_outgoing?(node, source_ids, context)
      return false if terminal_node?(node)
      return false if source_ids.include?(node[:id])

      !loop_body_leaf?(node[:id], context)
    end

    def terminal_node?(node)
      TERMINAL_TYPES.include?(node[:type])
    end

    def loop_body_leaf?(node_id, context)
      node_map = context[:node_map]
      edges_by_target = context[:edges_by_target]
      cache = context[:loop_body_cache]

      return cache[node_id] if cache.key?(node_id)

      incoming_edges = edges_by_target[node_id] || []
      cache[node_id] = false
      return false if incoming_edges.empty?

      cache[node_id] = incoming_edges.all? { |edge| loop_body_parent_edge?(edge, node_map, context) }
    end

    def loop_body_parent_edge?(edge, node_map, context)
      source = node_map[edge[:source]]
      return true if direct_loop_body_edge?(source, edge)

      loop_body_leaf?(edge[:source], context)
    end

    def direct_loop_body_edge?(source, edge)
      source && LOOPING_NODE_TYPES.include?(source[:type]) && edge[:source_port] == "loop"
    end

    def check_dangling_edges(edges, node_ids, issues)
      edges.each do |edge|
        issues << "Edge #{edge[:id]} references missing source node" unless node_ids.include?(edge[:source])
        issues << "Edge #{edge[:id]} references missing target node" unless node_ids.include?(edge[:target])
      end
    end

    def check_warnings(nodes, edges, flow)
      warnings = []
      edge_context = build_edge_validation_context(nodes)
      check_unconnected_ports(nodes, edges, warnings, build_port_warning_context(nodes, edges))
      check_disconnected_inputs(nodes, edges, warnings, edge_context)
      check_no_starting_node(nodes, edges, warnings)
      check_global_variables(flow, warnings)
      warnings
    end

    def build_edge_validation_context(nodes)
      {
        node_map: nodes.index_by { |node| node[:id] },
        output_port_cache: {},
      }
    end

    def check_invalid_edge_ports(edges, issues, context)
      edges.each do |edge|
        next unless invalid_edge_port?(edge, context)

        source = context[:node_map][edge[:source]]
        available_ports = source_output_ports(source, context)
        issues << "Edge #{edge[:id]} uses invalid source port `#{normalized_edge_source_port(edge)}` for node " \
                  "\"#{source[:name]}\" (#{source[:type]}). Available ports: #{available_ports.join(", ")}"
      end
    end

    def check_disconnected_inputs(nodes, edges, warnings, context)
      edges_by_target = edges.group_by { |edge| edge[:target] }

      nodes.each do |node|
        next unless disconnected_input?(node, edges_by_target, context)

        warnings << disconnected_input_warning(node)
      end
    end

    def disconnected_input?(node, edges_by_target, context)
      incoming_edges = edges_by_target[node[:id]] || []
      return false if incoming_edges.empty?
      return false if incoming_edges.any? { |edge| valid_edge_port?(edge, context) }

      incoming_edges.all? { |edge| invalid_edge_port?(edge, context) }
    end

    def disconnected_input_warning(node)
      "Node \"#{node[:name]}\" (#{node[:type]}) has no valid incoming connections; " \
        "its input is effectively disconnected"
    end

    def build_port_warning_context(nodes, edges)
      {
        node_map: nodes.index_by { |node| node[:id] },
        edges_by_target: edges.group_by { |edge| edge[:target] },
        nested_loop_body_cache: {},
      }
    end

    def check_unconnected_ports(nodes, edges, warnings, context)
      nodes.each do |node|
        ports = output_port_keys(node)
        next if ports.nil? || ports.size <= 1

        connected = edges.select { |e| e[:source] == node[:id] }.to_set { |e| e[:source_port] }
        missing = filter_optional_nested_done_ports(node, ports - connected.to_a, context)
        next if missing.empty?

        warnings << "Node \"#{node[:name]}\" (#{node[:type]}) has unconnected ports: #{missing.join(", ")}"
      end
    end

    def filter_optional_nested_done_ports(node, missing_ports, context)
      return missing_ports unless missing_ports.include?("done")
      return missing_ports unless LOOPING_NODE_TYPES.include?(node[:type])
      return missing_ports unless nested_loop_body_member?(node[:id], context)

      missing_ports - ["done"]
    end

    def nested_loop_body_member?(node_id, context)
      cache = context[:nested_loop_body_cache]
      return cache[node_id] if cache.key?(node_id)

      incoming_edges = context[:edges_by_target][node_id] || []
      cache[node_id] = false
      return false if incoming_edges.empty?

      cache[node_id] = incoming_edges.any? { |edge| loop_body_ancestor_edge?(edge, context) }
    end

    def loop_body_ancestor_edge?(edge, context)
      source = context[:node_map][edge[:source]]
      return true if direct_loop_body_edge?(source, edge)

      nested_loop_body_member?(edge[:source], context)
    end

    def output_port_keys(node)
      node_class = MissionNodePlugin.resolve(node[:type])
      return [] unless node_class

      node_class.output_ports_for(node[:data]).map { |port| port[:key].to_s }
    end

    def source_output_ports(node, context)
      cache = context[:output_port_cache]
      cache[node[:id]] ||= output_port_keys(node)
    end

    def valid_edge_port?(edge, context)
      source = context[:node_map][edge[:source]]
      return false unless source

      source_output_ports(source, context).include?(normalized_edge_source_port(edge))
    end

    def invalid_edge_port?(edge, context)
      source = context[:node_map][edge[:source]]
      return false unless source

      available_ports = source_output_ports(source, context)
      available_ports.any? && available_ports.exclude?(normalized_edge_source_port(edge))
    end

    def normalized_edge_source_port(edge)
      edge[:source_port].presence || "default"
    end

    def check_no_starting_node(nodes, edges, warnings)
      runnable_nodes = nodes
      return if runnable_nodes.empty?

      target_ids = edges.to_set { |e| e[:target] }
      starting = runnable_nodes.reject { |n| target_ids.include?(n[:id]) }
      warnings << "No starting node found (all nodes have incoming edges)" if starting.empty?
    end

    def check_global_variables(flow, warnings)
      globals = flow["global_variables"] || []
      return if globals.empty?

      check_duplicate_global_keys(globals, warnings)
      check_global_values_and_types(globals, warnings)
    end

    def check_duplicate_global_keys(globals, warnings)
      dups = globals.pluck("key").tally.select { |_, count| count > 1 }.keys
      warnings << "Duplicate global variable keys: #{dups.join(", ")}" if dups.any?
    end

    def check_global_values_and_types(globals, warnings)
      globals.each do |var|
        warnings << "Global variable \"#{var["key"]}\" has no value" if var["value"].blank?
        unless Missions::FlowEditor::VALID_VARIABLE_TYPES.include?(var["type"])
          warnings << "Global variable \"#{var["key"]}\" has invalid type: #{var["type"]}"
        end
      end
    end
  end
end
