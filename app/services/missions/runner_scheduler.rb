# frozen_string_literal: true

require "securerandom"

module Missions
  # Branch-local queue used by the runner to process linear work without
  # recursive traversal. Concurrent fan-out and loop bodies fork a fresh
  # scheduler that shares the global execution counter.
  class RunnerScheduler
    WorkItem = Data.define(:node_id, :incoming_edge_id, :runtime_state) do
      def to_h
        {
          "node_id" => node_id,
          "incoming_edge_id" => incoming_edge_id,
          "runtime_state" => runtime_state.transform_keys(&:to_s),
        }
      end
    end

    attr_reader :execution_count, :frontier_id

    def self.start(node_id:, execution_count: nil, context: nil, frontier_id: nil, **work_item)
      new(execution_count:, context:, frontier_id:).tap do |scheduler|
        scheduler.enqueue(node_id, **work_item)
      end
    end

    def self.restore(frontier_id:, frontier_state:, execution_count:, context:)
      work_items = Array(frontier_state["ready"]).map { |item| build_work_item(item) }
      active_item = frontier_state["active"] ? build_work_item(frontier_state["active"]) : nil
      work_items.unshift(active_item) if active_item

      new(execution_count:, context:, frontier_id:, work_items:)
    end

    def initialize(execution_count: nil, context: nil, frontier_id: nil, work_items: nil)
      @execution_count = execution_count || ExecutionCounter.new
      @context = context
      @frontier_id = frontier_id || SecureRandom.uuid
      @work_items = Array(work_items)
      @active_work_item = nil
      @next_index = 0
      sync_frontier!
    end

    def enqueue(node_id, incoming_edge_id: nil, runtime_state: {})
      @work_items << self.class.build_work_item(
        "node_id" => node_id,
        "incoming_edge_id" => incoming_edge_id,
        "runtime_state" => runtime_state,
      )
      sync_frontier!
      self
    end

    def dequeue
      return if empty?

      item = @work_items[@next_index]
      @next_index += 1
      @active_work_item = item
      compact_processed_items!
      sync_frontier!
      item
    end

    def complete_active_work_item
      @active_work_item = nil
      sync_frontier!
    end

    def refresh_active_work_item(runtime_state:)
      return unless @active_work_item

      @active_work_item = self.class.build_work_item(@active_work_item.to_h.merge("runtime_state" => runtime_state))
      sync_frontier!
    end

    def fork(node_id: nil, incoming_edge_id: nil, runtime_state: {})
      self.class.new(execution_count:, context: @context).tap do |scheduler|
        scheduler.enqueue(node_id, incoming_edge_id:, runtime_state:) if node_id
      end
    end

    def empty?
      @next_index >= @work_items.length
    end

    private

    class << self
      def build_work_item(item)
        WorkItem.new(
          node_id: work_item_value(item, "node_id", required: true).to_s,
          incoming_edge_id: work_item_value(item, "incoming_edge_id")&.to_s,
          runtime_state: work_item_runtime_state(item),
        )
      end

      private

      def work_item_value(item, key, required: false)
        return item[key] if item.key?(key)
        return item[key.to_sym] if item.key?(key.to_sym)

        raise KeyError, key if required

        nil
      end

      def work_item_runtime_state(item)
        (work_item_value(item, "runtime_state") || {}).transform_keys(&:to_s)
      end
    end

    def pending_work_items
      @work_items[@next_index..] || []
    end

    def sync_frontier!
      return unless @context

      @context.sync_scheduler_frontier(
        frontier_id,
        ready_items: pending_work_items.map(&:to_h),
        active_item: @active_work_item&.to_h,
      )
      @context.execution_count_value = execution_count.value
    end

    def compact_processed_items!
      return unless @next_index >= 32 && @next_index * 2 >= @work_items.length

      @work_items = @work_items[@next_index..] || []
      @next_index = 0
    end
  end
end
