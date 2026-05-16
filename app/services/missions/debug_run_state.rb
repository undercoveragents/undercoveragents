# frozen_string_literal: true

module Missions
  class DebugRunState
    include DebugRunStateProjection

    ITERATIVE_NODE_TYPES = ["iterator", "loop"].freeze

    attr_reader :mission, :run

    delegate :active?, to: :run

    def initialize(mission:, run:)
      @mission = mission
      @run = run
    end

    def status_payload
      {
        run_id: run.id,
        status: run.status,
        current_node_id: run.current_node_id,
        execution_log:,
        variables:,
        node_outputs:,
        node_states:,
        edge_states:,
        error: run.error,
        started_at: run.started_at&.iso8601(3),
        completed_at: run.completed_at&.iso8601(3),
        duration_ms:,
      }
    end

    def execution_log
      @execution_log ||= enrich_execution_log(raw_execution_log)
    end

    def variables
      @variables ||= sanitize_variables(run.variables || {})
    end

    def filtered_variables(fallback: :all, keys: global_variable_keys)
      normalized_keys = Array(keys).filter_map { |key| key.to_s.presence }
      return fallback == :all ? variables : {} if normalized_keys.empty?

      variables.slice(*normalized_keys)
    end

    def node_outputs
      @node_outputs ||= stringify_run_state(execution_state["node_outputs"])
    end

    def node_states
      @node_states ||= stringify_run_state(execution_state["node_states"])
    end

    def edge_states
      @edge_states ||= stringify_run_state(execution_state["edge_states"])
    end

    def node_completion_counts
      @node_completion_counts ||= compute_node_completion_counts(execution_log)
    end

    private

    def execution_state
      run.execution_state || {}
    end

    def flow_data
      @flow_data ||= run.flow_snapshot.presence || mission.flow_data || {}
    end

    def current_flow_data
      @current_flow_data ||= mission.flow_data || {}
    end

    def raw_execution_log
      execution_state["execution_log"] || []
    end

    def sanitize_variables(vars)
      vars.reject { |key, _| key.to_s.start_with?("_") }
    end

    def stringify_run_state(value)
      value.is_a?(Hash) ? value.transform_keys(&:to_s) : {}
    end

    def enrich_execution_log(log)
      nodes_by_id = current_flow_nodes.merge(snapshot_flow_nodes)

      log.map do |entry|
        enriched_entry = entry.dup
        enrich_entry_duration(enriched_entry)
        enrich_entry_node_label(enriched_entry, nodes_by_id)
        enriched_entry
      end
    end

    def enrich_entry_duration(entry)
      return unless entry["duration_ms"].nil?

      started_at = parse_time(entry["started_at"])
      finished_at = parse_time(entry["finished_at"])
      return unless started_at && finished_at

      entry["duration_ms"] = ((finished_at - started_at) * 1000).round(1)
    end

    def parse_time(value)
      return if value.blank?

      Time.iso8601(value)
    rescue ArgumentError
      nil
    end

    def enrich_entry_node_label(entry, nodes_by_id)
      return if entry["node_label"].present?

      node_data = nodes_by_id[entry["node_id"]]&.dig("data") || {}
      entry["node_label"] = node_data["label"].presence || node_data["name"].presence
    end

    def current_flow_nodes
      @current_flow_nodes ||= (current_flow_data["nodes"] || []).index_by { |node| node["id"] }
    end

    def snapshot_flow_nodes
      @snapshot_flow_nodes ||= (flow_data["nodes"] || []).index_by { |node| node["id"] }
    end

    def compute_node_completion_counts(log)
      log.each_with_object(Hash.new(0)) do |entry, counts|
        next unless entry["status"].to_s == "success"

        node_id = entry["node_id"].to_s
        node_type = entry["node_type"].to_s
        next_port = entry["next_port"].to_s

        if ITERATIVE_NODE_TYPES.include?(node_type) && next_port == "done"
          counts[node_id] = iterator_completion_count(node_type, entry["output"], counts[node_id])
        else
          counts[node_id] += 1
        end
      end
    end

    def iterator_completion_count(node_type, output, current_count)
      return output.size if node_type == "iterator" && output.is_a?(Array)
      return current_count if node_type == "loop"

      current_count + 1
    end
  end
end
