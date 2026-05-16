# frozen_string_literal: true

module Missions
  # Scheduler lifecycle helpers for entry-node seeding and persisted frontier
  # restoration.
  module RunnerFrontierTraversal
    private

    def execute_graph(run, graph, context)
      graph.validate!
      entry_nodes = graph.trigger_nodes
      entry_nodes = graph.root_nodes if entry_nodes.empty?
      scheduler = build_scheduler(context:, execution_count: ExecutionCounter.new(value: context.execution_count_value))
      entry_nodes.each do |entry_node|
        scheduler.enqueue(entry_node["id"], runtime_state: context.snapshot_runtime_state)
      end

      drain_scheduler(RunnerFrame.new(run:, graph:, context:, scheduler:))
    end

    def execute_from(run, graph, context, start_node_id)
      restored_schedulers = restore_schedulers(context)
      return drain_restored_schedulers(run, graph, context, restored_schedulers) if restored_schedulers.any?

      execute_node_and_follow(run, graph, context, start_node_id)
    end

    def execute_node_and_follow(run, graph, context, node_id, options = {})
      scheduler = build_scheduler(context:, execution_count: options[:execution_count])
      scheduler.enqueue(
        node_id,
        incoming_edge_id: options[:incoming_edge]&.dig("id"),
        runtime_state: context.snapshot_runtime_state,
      )
      drain_scheduler(RunnerFrame.new(run:, graph:, context:, scheduler:))
    end

    def build_scheduler(context:, execution_count: nil)
      RunnerScheduler.new(execution_count:, context:)
    end

    def restore_schedulers(context)
      return [] unless context.scheduler_frontiers?

      execution_count = ExecutionCounter.new(value: context.execution_count_value)

      context.scheduler_frontiers.sort_by { |frontier_id, _| frontier_id }.map do |frontier_id, frontier_state|
        RunnerScheduler.restore(frontier_id:, frontier_state:, execution_count:, context:)
      end
    end

    def drain_restored_schedulers(run, graph, context, schedulers)
      if schedulers.one?
        drain_scheduler(run, graph, context, schedulers.first)
      else
        execute_concurrently(schedulers, context:) do |scheduler|
          drain_scheduler(run, graph, context, scheduler)
        end
      end
    end
  end
end
