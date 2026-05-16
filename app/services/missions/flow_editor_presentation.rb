# frozen_string_literal: true

module Missions
  module FlowEditorPresentation
    private

    def requested_node_position(flow, attributes)
      near_x, near_y = resolve_near_position(flow, attributes[:near_node_id]) if attributes[:near_node_id].present?
      {
        x: attributes[:position_x] || near_x || auto_x(flow),
        y: attributes[:position_y] || near_y || auto_y(flow),
      }
    end

    def resolve_near_position(flow, near_node_id)
      reference_node = flow["nodes"].find { |node| node["id"] == near_node_id }
      position = normalized_position(reference_node)
      return unless position

      [position[:x] + self.class::NEAR_NODE_X_OFFSET, position[:y]]
    end

    def auto_x(flow)
      max_right = flow["nodes"].filter_map do |node|
        position = normalized_position(node)
        next unless position

        position[:x] + normalized_width(node)
      end.max

      return 250.0 unless max_right

      max_right + 80.0
    end

    def auto_y(flow)
      flow["nodes"].filter_map { |node| normalized_position(node)&.dig(:y) }.first || 150.0
    end

    def normalized_position(node)
      return unless node.is_a?(Hash)

      position = node["position"]
      return unless position.is_a?(Hash)

      x = numeric_layout_value(position["x"])
      y = numeric_layout_value(position["y"])
      return unless x && y

      { x:, y: }
    end

    def normalized_width(node)
      numeric_layout_value(node.dig("style", "width")) || self.class::DEFAULT_NODE_WIDTH
    end

    def numeric_layout_value(value)
      return value.to_f if value.is_a?(Numeric)

      Float(value, exception: false)
    end

    def summarize_persisted_node(node_id)
      flow = current_flow
      node = flow["nodes"].find { |entry| entry["id"] == node_id }
      return unless node

      summarize_node(node, variable_name: Missions::NodeVariableNameResolver.for_node(node_id, flow))
    end

    def summarize_node(node, variable_name: nil)
      data = node["data"] || {}
      {
        id: node["id"],
        type: node["type"],
        name: data["label"] || data["name"],
        variable_name: variable_name || data["name"],
        position: node["position"],
        config: data.except("label", "name", "icon", "color", "output_ports"),
      }
    end

    def summarize_edge(edge)
      {
        id: edge["id"],
        source: edge["source"],
        target: edge["target"],
        source_port: edge["sourceHandle"] || "default",
      }
    end

    def error(message)
      { error: message }
    end
  end
end
