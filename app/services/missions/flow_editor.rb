# frozen_string_literal: true

module Missions
  # Service for programmatically editing a Mission's flow_data.
  # Used by mission designer agent tools to add/update/remove nodes and edges.
  class FlowEditor
    include FlowEditorGlobalVariables
    include FlowEditorPresentation

    NEAR_NODE_X_OFFSET = 300.0
    DEFAULT_NODE_WIDTH = 260.0

    attr_reader :mission

    def initialize(mission)
      @mission = mission
    end

    # Returns a compact representation of the current flow.
    def read_flow
      flow = current_flow
      variable_names = Missions::NodeVariableNameResolver.build_map(flow)

      {
        nodes: flow["nodes"].map { |node| summarize_node(node, variable_name: variable_names[node["id"].to_s]) },
        edges: flow["edges"].map { |e| summarize_edge(e) },
        global_variables: flow["global_variables"] || [],
        validation_errors: NodeConfigValidator.validate_flow(flow),
      }
    end

    # Adds a node to the flow. Returns the new node hash or an error.
    def add_node(**attributes)
      type = attributes[:type]
      meta = MissionNodePlugin.metadata_for(type)
      return error("Unknown node type: #{type}") unless meta

      flow = current_flow
      singleton_error = validate_singleton_addition(flow, type, meta)
      return singleton_error if singleton_error

      node = build_requested_node(flow, meta, attributes)
      save_with_undo!(flow) { flow["nodes"] << node }

      { node: summarize_persisted_node(node["id"]) }
    end

    def validate_singleton_addition(flow, type, meta)
      return unless meta[:singleton] && flow["nodes"].any? { |node| node["type"] == type }

      error("Only one #{meta[:label]} node is allowed per mission")
    end

    def build_requested_node(flow, meta, attributes)
      type = attributes[:type]
      position = requested_node_position(flow, attributes)

      build_node(
        type:,
        name: attributes[:name] || meta[:label],
        config: normalize_node_config(type, attributes[:config] || {}),
        position_x: position[:x],
        position_y: position[:y],
      )
    end

    # Updates a node's data. Merges the given data into the existing node data.
    def update_node(node_id:, data:)
      flow = current_flow
      node = flow["nodes"].find { |n| n["id"] == node_id }
      return error("Node not found: #{node_id}") unless node

      save_with_undo!(flow) do
        merged_data = (node["data"] || {}).merge(data)
        node["data"] = normalize_node_data(node["type"], merged_data)
      end

      { node: summarize_persisted_node(node_id) }
    end

    # Removes a node and all connected edges.
    def remove_node(node_id:)
      flow = current_flow
      node = flow["nodes"].find { |n| n["id"] == node_id }
      return error("Node not found: #{node_id}") unless node

      removed_edges = count_edges_for_node(flow, node_id)
      variable_name = Missions::NodeVariableNameResolver.for_node(node_id, flow)

      save_with_undo!(flow) do
        flow["nodes"].reject! { |n| n["id"] == node_id }
        flow["edges"].reject! { |edge| edge_touches_node?(edge, node_id) }
      end

      { removed_node: summarize_node(node, variable_name:), removed_edges_count: removed_edges }
    end

    # Adds an edge between two nodes.
    def add_edge(source_node_id:, target_node_id:, source_port: nil)
      flow = current_flow
      source_node = find_node(flow, source_node_id)
      return error("Source node not found: #{source_node_id}") unless source_node

      target_node = find_node(flow, target_node_id)
      return error("Target node not found: #{target_node_id}") unless target_node

      return error("Cannot connect a node to itself") if source_node_id == target_node_id

      resolved_source_port = resolve_source_port(source_node, source_port)
      return resolved_source_port if resolved_source_port.is_a?(Hash)

      return error("Edge already exists") if edge_exists?(flow, source_node_id, target_node_id, resolved_source_port)

      boundary_error = validate_edge_boundary(
        flow,
        source_node_id:,
        target_node_id:,
        source_port: resolved_source_port,
      )
      return error(boundary_error) if boundary_error

      edge = build_edge(source_node_id:, target_node_id:, source_port: resolved_source_port)

      save_with_undo!(flow) { flow["edges"] << edge }

      { edge: summarize_edge(edge) }
    end

    # Removes edges matching the criteria.
    def remove_edge(source_node_id: nil, target_node_id: nil, edge_id: nil)
      flow = current_flow
      removed = []
      criteria = { source_node_id:, target_node_id:, edge_id: }

      save_with_undo!(flow) do
        flow["edges"].reject! do |edge|
          match = edge_matches_removal?(edge, criteria)
          removed << edge if match
          match
        end
      end

      return error("No matching edge found") if removed.empty?

      { removed_edges: removed.map { |e| summarize_edge(e) } }
    end

    def edge_matches_removal?(edge, criteria)
      return edge["id"] == criteria[:edge_id] if criteria[:edge_id]

      (criteria[:source_node_id].nil? || edge["source"] == criteria[:source_node_id]) &&
        (criteria[:target_node_id].nil? || edge["target"] == criteria[:target_node_id])
    end

    private :validate_singleton_addition, :build_requested_node, :edge_matches_removal?

    private

    def current_flow
      flow = mission.reload.flow_data || {}
      flow["nodes"] ||= []
      flow["edges"] ||= []
      flow
    end

    def save_with_undo!(flow)
      old_flow = flow.deep_dup
      yield
      normalized = normalize_flow(flow)
      mission.update!(flow_data: normalized)
      mission.push_undo_snapshot!(old_flow) if old_flow != normalized
      broadcast_flow_update!(normalized)
    end

    def broadcast_flow_update!(_flow)
      Turbo::StreamsChannel.broadcast_append_to(
        "mission_flow_#{mission.id}",
        target: "mission-flow-updates",
        html: "<div data-refresh=\"true\"></div>",
      )
    rescue StandardError => e
      Rails.logger.warn("FlowEditor broadcast failed: #{e.message}")
    end

    def find_node(flow, node_id)
      flow["nodes"].find { |n| n["id"] == node_id }
    end

    def edge_exists?(flow, source_id, target_id, port)
      flow["edges"].any? { |e| e["source"] == source_id && e["target"] == target_id && e["sourceHandle"] == port }
    end

    def resolve_source_port(source_node, source_port)
      ports = available_output_ports_for(source_node)
      if ports.empty?
        return error("Node \"#{node_display_name(source_node)}\" (#{source_node["type"]}) has no output ports")
      end

      requested_port = source_port.presence
      return ports.first if requested_port.blank? && ports.one?

      if requested_port.blank?
        return error(
          "Source port is required for node \"#{node_display_name(source_node)}\" " \
          "(#{source_node["type"]}). Available ports: #{ports.join(", ")}",
        )
      end

      return requested_port if ports.include?(requested_port)

      error(
        "Invalid source port `#{requested_port}` for node \"#{node_display_name(source_node)}\" " \
        "(#{source_node["type"]}). Available ports: #{ports.join(", ")}",
      )
    end

    def available_output_ports_for(node)
      node_class = MissionNodePlugin.resolve(node["type"])
      return [] unless node_class

      node_class.output_ports_for(node["data"] || {}).map { |port| port[:key].to_s }
    end

    def node_display_name(node)
      node.dig("data", "label") || node.dig("data", "name") || node["type"]
    end

    def validate_edge_boundary(flow, source_node_id:, target_node_id:, source_port:)
      Missions::LoopBodyBoundaryValidator.error_for_candidate_edge(
        flow_data: flow,
        source_node_id:,
        target_node_id:,
        source_port:,
      )
    end

    def build_edge(source_node_id:, target_node_id:, source_port:)
      {
        "id" => "edge-#{SecureRandom.hex(6)}",
        "source" => source_node_id,
        "sourceHandle" => source_port,
        "target" => target_node_id,
        "targetHandle" => nil,
      }
    end

    def count_edges_for_node(flow, node_id)
      flow["edges"].count { |edge| edge_touches_node?(edge, node_id) }
    end

    def edge_touches_node?(edge, node_id)
      edge["source"] == node_id || edge["target"] == node_id
    end

    def normalize_flow(flow)
      Missions::FlowPersistenceNormalizer.normalize(flow, tenant: mission.operation.tenant)
    end

    def normalize_node_config(type, config)
      normalize_node_data(type, config.stringify_keys)
    end

    def normalize_node_data(type, data)
      Missions::LlmNodeDefaults.apply(type:, data:, tenant: mission.operation.tenant)
    end

    def build_node(type:, name:, config:, position_x:, position_y:)
      meta = MissionNodePlugin.metadata_for(type) || {}
      data = {
        "label" => name,
        "name" => Missions::FlowPersistenceNormalizer.sanitize_node_name(name),
        "icon" => meta[:icon],
        "color" => meta[:color],
        "output_ports" => meta[:output_ports],
      }.compact.merge(config.stringify_keys)

      {
        "id" => "node-#{SecureRandom.hex(6)}",
        "type" => type,
        "position" => { "x" => position_x.to_f, "y" => position_y.to_f },
        "data" => data,
      }
    end
  end
end
