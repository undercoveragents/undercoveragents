# frozen_string_literal: true

module Missions
  module RunnerLoopFlow
    private

    def execute_loop_flow(frame, node_id, node_data)
      frame.context.set_variable("_current_node_data", node_data)
      iteration = frame.context.loop_iteration(node_id)
      max = loop_max_iterations(node_data)

      loop do
        break if halt_loop_flow?(frame.run, frame.scheduler, iteration, max)

        return if execute_loop_iteration?(frame, node_id, node_data, iteration)

        iteration = next_loop_iteration(frame.context, node_id, iteration)
      end

      complete_loop_flow(frame, node_id, node_data)
    end

    def loop_max_iterations(node_data)
      [(node_data["max_iterations"] || self.class::MAX_LOOP_ITERATIONS).to_i, self.class::MAX_LOOP_ITERATIONS].min
    end

    def complete_loop_flow(frame, node_id, node_data)
      frame.context.log_execution(loop_done_execution(frame, node_id, node_data))
      frame.scheduler.complete_active_work_item
      frame.context.clear_loop_iteration(node_id)
      on_loop_done(frame.run, frame.graph, frame.context, node_id)
      follow_edges(frame, node_id, "done", strict: true)
    end

    def loop_done_execution(frame, node_id, node_data)
      NodeExecution.new(
        node_id:, node_type: "loop", status: :success,
        input: safe_serialize(node_input_snapshot("loop", node_data, frame.context)),
        output: safe_serialize(frame.context.current_input), next_port: "done",
        started_at: Time.current, finished_at: Time.current, error: nil,
      )
    end

    def execute_loop_iteration?(frame, node_id, node_data, iteration)
      prepare_loop_iteration(frame.context, node_id, node_data, iteration)
      result = execute_loop_handler(frame, node_id, node_data)

      return finish_loop?(frame, node_id) if result.next_port == "done" || result.failure?

      continue_loop_iteration(frame, node_id, iteration)
      false
    end

    def execute_loop_handler(frame, node_id, node_data)
      frame.scheduler.execution_count.increment
      frame.context.execution_count_value = frame.scheduler.execution_count.value
      input_snapshot = node_input_snapshot("loop", node_data, frame.context)
      result = resolve_handler("loop").execute(frame.context)
      log_loop_iteration(frame.context, node_id, result, input_snapshot)
      frame.scheduler.refresh_active_work_item(runtime_state: frame.context.snapshot_runtime_state)
      persist_state(frame.run, frame.context, current_node_id: node_id)
      result
    end

    def continue_loop_iteration(frame, node_id, iteration)
      checkpoint_loop_iteration(frame, node_id, iteration)
      follow_edges(frame, node_id, self.class::LOOP_PORT, strict: true, dispatch: :branch)
      checkpoint_loop_iteration(frame, node_id, iteration + 1)
    end

    def prepare_loop_iteration(context, node_id, node_data, iteration)
      context.set_variable("_current_node_id", node_id)
      context.set_variable("_current_node_type", "loop")
      context.set_loop_iteration(node_id, iteration)
      context.set_runtime_variable("iteration", iteration)
      context.set_variable("_current_node_data", node_data)
    end

    def checkpoint_loop_iteration(frame, node_id, iteration)
      frame.context.set_loop_iteration(node_id, iteration)
      checkpoint_active_frontier(frame.run, frame.context, node_id, frame.scheduler)
    end

    def log_loop_iteration(context, node_id, result, input_snapshot)
      execution = NodeExecution.new(
        node_id:, node_type: "loop", status: result.status,
        input: safe_serialize(input_snapshot),
        output: safe_serialize(result.output), next_port: result.next_port,
        started_at: Time.current, finished_at: Time.current, error: nil,
      )
      context.log_execution(execution)
    end

    def finish_loop?(*args)
      frame, node_id = loop_finish_args(args)

      frame.scheduler.complete_active_work_item unless frame.context.execution_log.last&.status == :failure
      frame.context.clear_loop_iteration(node_id)
      on_loop_done(frame.run, frame.graph, frame.context, node_id)
      follow_edges(frame, node_id, "done", strict: true)
      true
    end

    def halt_loop_flow?(run, scheduler, iteration, max)
      scheduler.execution_count.value >= self.class::MAX_TOTAL_EXECUTIONS ||
        iteration >= max ||
        run.reload.cancelled?
    end

    def next_loop_iteration(context, node_id, iteration)
      context.loop_iteration(node_id, fallback: iteration + 1)
    end
  end
end
