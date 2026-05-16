# frozen_string_literal: true

module Missions
  module FlowDataSanitizer
    module_function

    def sanitize(flow_data)
      flow = flow_data.is_a?(Hash) ? flow_data : {}

      {
        "nodes" => Array(flow["nodes"]).grep(Hash).map { |node| sanitize_node(node) },
        "edges" => Array(flow["edges"]).grep(Hash).map(&:deep_stringify_keys),
      }.tap do |normalized|
        global_variables = Array(flow["global_variables"]).grep(Hash).map(&:deep_stringify_keys)
        normalized["global_variables"] = global_variables if global_variables.present?
      end
    end

    def parse_and_sanitize(value)
      sanitize(value.is_a?(String) ? JSON.parse(value) : value)
    rescue JSON::ParserError
      empty_flow
    end

    def empty_flow
      { "nodes" => [], "edges" => [] }
    end

    def sanitize_node(node)
      sanitized = node.deep_stringify_keys
      position = sanitized["position"].is_a?(Hash) ? sanitized["position"].deep_stringify_keys : {}

      sanitized["position"] = {
        "x" => position.key?("x") ? position["x"] : 0,
        "y" => position.key?("y") ? position["y"] : 0,
      }

      sanitized
    end
  end
end
