# frozen_string_literal: true

module Missions
  module ExecutionContextSchedulerState
    attr_reader :scheduler_frontiers, :execution_count_value

    def initialize_scheduler_state
      @scheduler_frontiers = {}
      @execution_count_value = 0
    end

    def sync_scheduler_frontier(frontier_id, ready_items:, active_item: nil)
      key = frontier_id.to_s
      frontier_state = {
        "ready" => Array(ready_items).map { |item| serialize_frontier_item(item) },
        "active" => active_item ? serialize_frontier_item(active_item) : nil,
      }

      if frontier_state["ready"].empty? && frontier_state["active"].nil?
        @scheduler_frontiers.delete(key)
      else
        @scheduler_frontiers[key] = frontier_state
      end
    end

    def scheduler_frontiers?
      @scheduler_frontiers.any?
    end

    def execution_count_value=(value)
      @execution_count_value = value.to_i
    end

    private

    def serialized_scheduler_frontiers
      @scheduler_frontiers.transform_values do |frontier_state|
        {
          "ready" => Array(frontier_state["ready"]).map { |item| serialize_frontier_item(item) },
          "active" => frontier_state["active"] ? serialize_frontier_item(frontier_state["active"]) : nil,
        }
      end
    end

    def serialize_frontier_item(item)
      raw = item.respond_to?(:to_h) ? item.to_h : item
      {
        "node_id" => frontier_value(raw, "node_id").to_s,
        "incoming_edge_id" => frontier_value(raw, "incoming_edge_id")&.to_s,
        "runtime_state" => serialized_hash(frontier_runtime_state(raw)),
      }
    end

    def frontier_value(raw, key)
      return raw[key] if raw.key?(key)
      return raw[key.to_sym] if raw.key?(key.to_sym)

      nil
    end

    def frontier_runtime_state(raw)
      (frontier_value(raw, "runtime_state") || {}).transform_keys(&:to_s)
    end
  end
end
