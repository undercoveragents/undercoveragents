# frozen_string_literal: true

module Missions
  module FlowPersistenceNormalizer
    module_function

    FLOAT_DATA_KEYS = ["temperature"].freeze
    INT_DATA_KEYS = ["max_iterations", "count", "offset", "duration", "status_code", "thinking_budget"].freeze
    INT_ARRAY_DATA_KEYS = ["tool_ids"].freeze
    TRANSIENT_NODE_KEYS = ["selected", "dragging", "resizing", "measured", "positionAbsolute", "width", "height"].freeze

    def parse_and_normalize(value, tenant: nil)
      return empty_flow if value.blank?

      normalize(value.is_a?(String) ? JSON.parse(value) : value, tenant:)
    rescue JSON::ParserError
      empty_flow
    end

    def normalize(flow, tenant: nil)
      sanitized = Missions::FlowDataSanitizer.sanitize(flow)

      {
        "nodes" => Array(sanitized["nodes"]).map { |node| normalize_node(node, tenant:) },
        "edges" => Missions::FlowEdgeNormalizer.normalize_all(Array(sanitized["edges"]).grep(Hash)),
      }.tap do |normalized|
        Missions::NodeVariableNameResolver.assign!(normalized)
        global_variables = sanitize_global_variables(Array(sanitized["global_variables"]).grep(Hash))
        normalized["global_variables"] = global_variables if global_variables.present?
      end
    end

    def normalize_node(node, tenant: nil)
      cleaned = node.except(*TRANSIENT_NODE_KEYS)
      sync_derived_name!(cleaned)
      apply_llm_node_defaults!(cleaned, tenant:)
      coerce_node_data_types!(cleaned)
      cleaned
    end

    def sanitize_node_name(raw)
      Missions::NodeVariableNameResolver.sanitize(raw).to_s
    end

    def empty_flow
      Missions::FlowDataSanitizer.empty_flow
    end

    def sanitize_global_variables(global_variables)
      global_variables.map do |variable|
        variable.merge("key" => variable["key"].to_s.gsub(/[^a-zA-Z0-9_]/, "_"))
      end
    end

    def sync_derived_name!(node)
      data = node["data"]
      return node unless data.is_a?(Hash)

      if data["name"].present?
        data["name"] = sanitize_node_name(data["name"])
      elsif data["label"].present?
        data["name"] = sanitize_node_name(data["label"])
      end

      node
    end

    def coerce_node_data_types!(node)
      data = node["data"]
      return node unless data.is_a?(Hash)

      FLOAT_DATA_KEYS.each { |key| coerce_float(data, key) }
      INT_DATA_KEYS.each { |key| coerce_int(data, key) }
      INT_ARRAY_DATA_KEYS.each { |key| coerce_int_array(data, key) }
      node
    end

    def apply_llm_node_defaults!(node, tenant: nil)
      data = node["data"]
      return node unless data.is_a?(Hash)

      node["data"] = Missions::LlmNodeDefaults.apply(type: node["type"], data:, tenant:)
      node
    end

    def coerce_float(data, key)
      data[key] = Float(data[key]) if data[key].is_a?(String) && data[key].match?(/\A-?\d+(\.\d+)?\z/)
    end

    def coerce_int(data, key)
      data[key] = Integer(data[key]) if data[key].is_a?(String) && data[key].match?(/\A-?\d+\z/)
    end

    def coerce_int_array(data, key)
      values = data[key]
      return unless values.is_a?(Array)

      data[key] = values.filter_map { |value| Integer(value, exception: false) }
    end
  end
end
