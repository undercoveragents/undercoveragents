# frozen_string_literal: true

module Missions
  module DebugRunStateProjection
    def canvas_node_states
      return {} unless active?

      @canvas_node_states ||= build_canvas_node_states
    end

    def canvas_edge_states
      return {} unless active?

      @canvas_edge_states ||= edge_states.transform_values { |state| { status: state } }
    end

    def node_event_payloads
      @node_event_payloads ||= execution_log.filter_map { |entry| node_event_payload(entry) }
    end

    def persisted_node_state_payloads
      @persisted_node_state_payloads ||= node_states.map do |node_id, state|
        {
          "node-id" => node_id,
          "node-type" => state["node_type"],
          state: state["status"],
          "next-port" => state["next_port"],
          "duration-ms" => state["duration_ms"],
          error: state["error"],
          "completed-count" => state["completed_count"],
        }.compact
      end
    end

    def edge_event_payloads
      @edge_event_payloads ||= edge_states.map do |edge_id, state|
        { "edge-id" => edge_id, "edge-state" => state }
      end
    end

    def global_variable_keys
      @global_variable_keys ||= flow_global_variables.filter_map { |value| value["key"].presence }
    end

    def duration_ms
      return nil unless run.duration

      (run.duration * 1000).round(1)
    end

    private

    def flow_global_variables
      flow_data["global_variables"].presence || current_flow_data["global_variables"] || []
    end

    def build_canvas_node_states
      latest_by_node = initial_canvas_node_states
      execution_log.each { |entry| latest_by_node[canvas_node_id(entry)] = entry }

      latest_by_node.transform_values do |entry|
        normalized = normalized_canvas_node_state(entry)
        normalized[:completed_count] = [
          node_completion_counts[canvas_node_id(entry)],
          normalized[:completed_count],
          0,
        ].compact.first
        normalized
      end
    end

    def initial_canvas_node_states
      node_states.each_with_object({}) do |(node_id, state), result|
        result[node_id.to_s] = normalized_canvas_node_state(state)
      end
    end

    def normalized_canvas_node_state(entry)
      {
        status: canvas_state_value(entry, :status),
        next_port: canvas_state_value(entry, :next_port),
        duration_ms: canvas_state_value(entry, :duration_ms),
        error: canvas_state_value(entry, :error),
        node_type: canvas_state_value(entry, :node_type),
        completed_count: canvas_state_value(entry, :completed_count, default: 0),
      }
    end

    def canvas_node_id(entry)
      (entry[:node_id] || entry["node_id"]).to_s
    end

    def canvas_state_value(entry, key, default: nil)
      entry[key] || entry[key.to_s] || default
    end

    def node_event_payload(entry)
      node_id = canvas_node_id(entry)
      payload = {
        "node-id" => node_id,
        "node-type" => entry_value(entry, :node_type),
        state: entry_value(entry, :status),
        "next-port" => entry_value(entry, :next_port),
        "duration-ms" => entry_value(entry, :duration_ms),
        error: entry_value(entry, :error),
      }.compact

      completed_count = node_completion_counts[node_id]
      payload["completed-count"] = completed_count if completed_count&.positive?
      payload
    end

    def entry_value(entry, key)
      entry[key] || entry[key.to_s]
    end
  end
end
