# frozen_string_literal: true

module Missions
  # Shared concurrency helpers for branch fan-out.
  module RunnerConcurrency
    private

    def execute_concurrently(items, context: nil, &)
      errors = []
      runtime_state = context&.snapshot_runtime_state

      output_reached = Async do |task|
        tasks = build_concurrent_tasks(items, context, runtime_state, &)
        wait_for_concurrent_tasks(task, tasks, errors)
      end.wait

      raise output_reached if output_reached
      raise errors.first if errors.any?
    end

    def build_concurrent_tasks(items, context, runtime_state, &)
      items.map do |item|
        Async do
          context&.inherit_runtime_state(runtime_state)
          yield item
        ensure
          context&.clear_runtime_state_for_current_task
        end
      end
    end

    def wait_for_concurrent_tasks(parent_task, tasks, errors)
      output_reached = nil

      tasks.each do |task|
        task.wait
      rescue OutputReached => e
        output_reached ||= e
        parent_task.stop
      rescue StandardError => e
        errors << e
      end

      output_reached
    end
  end
end
