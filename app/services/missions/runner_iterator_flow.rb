# frozen_string_literal: true

module Missions
  module RunnerIteratorFlow
    private

    def execute_iterator_flow(*args)
      frame, node_id, node_data = iterator_flow_args(args)

      frame.context.set_variable("_current_node_data", node_data)
      collection, results, start_index = restore_or_start_iterator(frame, node_id, node_data)
      return unless collection

      execute_iterator_iterations(frame, node_id, collection, start_index, results)
      finalize_iterator_flow(frame, node_id, node_data, collection, results)
    end

    def execute_iterator_iterations(frame, node_id, collection, start_index, results)
      if iterator_parallel?(frame.context.iterator_state(node_id))
        execute_parallel_iterator_iterations(frame, node_id, collection, start_index, results)
      else
        execute_sequential_iterator_iterations(frame, node_id, collection, start_index, results)
      end
    end

    def start_iterator_flow(frame, node_id, node_data)
      initial_result = run_iterator_start_handler(frame, node_id, node_data)

      raise ExecutionError, "Iterator node '#{node_id}' failed: #{initial_result.output}" if initial_result.failure?

      return complete_empty_iterator_flow(frame, node_id) if initial_result.next_port == "done"

      checkpoint_active_frontier(frame.run, frame.context, node_id, frame.scheduler)
      :loop
    end

    def run_iterator_start_handler(frame, node_id, node_data)
      frame.scheduler.execution_count.increment
      frame.context.execution_count_value = frame.scheduler.execution_count.value
      initial_result = resolve_handler("iterator").execute(frame.context)
      record_iterator_start_result(frame, node_id, node_data, initial_result)
      initial_result
    end

    def record_iterator_start_result(frame, node_id, node_data, initial_result)
      log_iterator_execution(frame.context, node_id, node_data, initial_result)
      frame.context.store_node_output(node_id, initial_result.output)
      apply_iterator_result_variables(frame.context, initial_result)
      register_node_scoped_variables(frame.context, node_id, node_data, initial_result)
      checkpoint_active_frontier(frame.run, frame.context, node_id, frame.scheduler)
    end

    def complete_empty_iterator_flow(frame, node_id)
      frame.context.clear_iterator_state(node_id)
      frame.scheduler.complete_active_work_item
      on_iterator_loop_done(frame.run, frame.graph, frame.context, node_id)
      follow_edges(frame, node_id, "done", strict: true)
      :done
    end

    def log_iterator_execution(context, node_id, node_data, result)
      execution = NodeExecution.new(
        node_id:, node_type: "iterator", status: result.status,
        input: safe_serialize(node_input_snapshot("iterator", node_data, context)),
        output: safe_serialize(result.output), next_port: result.next_port,
        started_at: Time.current, finished_at: Time.current,
        error: result.failure? ? result.output.to_s : nil,
      )
      context.log_execution(execution)
    end

    def apply_iterator_result_variables(context, result)
      result.variables.each do |key, value|
        if self.class::ITERATOR_RUNTIME_KEYS.include?(key.to_s)
          context.set_runtime_variable(key, value)
        else
          context.set_variable(key, value)
        end
      end
    end

    def prepare_iterator_iteration(context, node_id, collection, index, results)
      item = collection[index]
      context.set_iterator_state(node_id, collection:, index:, total: collection.size, results: results.dup)
      context.set_runtime_variable("item", item)
      context.set_runtime_variable("index", index)
      context.set_runtime_variable("total", collection.size)
      context.current_input = item
    end

    def restore_or_start_iterator(frame, node_id, node_data)
      state = frame.context.iterator_state(node_id)
      return iterator_state_values(state) if state["collection"]

      return [nil, [], 0] if start_iterator_flow(frame, node_id, node_data) == :done

      iterator_state_values(frame.context.iterator_state(node_id))
    end

    def iterator_state_values(state)
      [state["collection"] || [], Array(state["results"]), state.fetch("index", 0).to_i]
    end

    def execute_sequential_iterator_iterations(frame, node_id, collection, start_index, results)
      start_index.upto(collection.size - 1) do |index|
        break if halt_iterator_flow?(frame.run, frame.scheduler)

        prepare_iterator_iteration(frame.context, node_id, collection, index, results)
        checkpoint_active_frontier(frame.run, frame.context, node_id, frame.scheduler)
        results << execute_iterator_iteration_branch(frame, node_id)
        persist_iterator_progress(
          frame.run,
          frame.context,
          node_id,
          iterator_progress_state(collection, index + 1, results),
          frame.scheduler,
        )
      end
    end

    def execute_parallel_iterator_iterations(*args)
      frame, node_id, collection, start_index, results = parallel_iterator_args(args)

      iterator_batches(
        collection.size,
        start_index,
        iterator_parallel_limit(frame.context.iterator_state(node_id)),
      ).each do |indices|
        break if halt_iterator_flow?(frame.run, frame.scheduler)

        execute_parallel_iterator_batch_window(frame, node_id, collection, indices, results)
      end
    end

    def execute_parallel_iterator_batch_window(frame, node_id, collection, indices, results)
      persist_iterator_progress(
        frame.run,
        frame.context,
        node_id,
        iterator_progress_state(collection, indices.first, results),
        frame.scheduler,
      )
      results.concat(execute_parallel_iterator_batch(frame, node_id, collection, indices, results))
      persist_iterator_progress(
        frame.run,
        frame.context,
        node_id,
        iterator_progress_state(collection, indices.last + 1, results),
        frame.scheduler,
      )
    end

    def execute_parallel_iterator_batch(frame, node_id, collection, indices, results)
      batch_results = Array.new(indices.size)
      branches = indices.each_with_index.map { |index, position| { index:, position: } }

      execute_concurrently(branches, context: frame.context) do |branch|
        batch_results[branch[:position]] = execute_parallel_iterator_branch(
          frame,
          node_id,
          collection,
          branch[:index],
          results,
        )
      end

      batch_results
    end

    def execute_parallel_iterator_branch(frame, node_id, collection, index, results)
      prepare_iterator_iteration(frame.context, node_id, collection, index, results)
      execute_iterator_iteration_branch(frame, node_id)
    end

    def execute_iterator_iteration_branch(frame, node_id)
      follow_edges(
        frame,
        node_id,
        self.class::LOOP_PORT,
        strict: true,
        dispatch: :branch,
      )

      frame.context.current_input
    end

    def iterator_progress_state(collection, next_index, results)
      { collection:, index: next_index, total: collection.size, results: results.dup }
    end

    def persist_iterator_progress(run, context, node_id, iterator_state, scheduler)
      context.set_iterator_state(node_id, **iterator_state)
      checkpoint_active_frontier(run, context, node_id, scheduler)
    end

    def finalize_iterator_flow(frame, node_id, node_data, collection, results)
      apply_iterator_done_result(frame, node_id, node_data, collection, results)
      frame.context.log_execution(iterator_done_execution(frame, node_id, node_data, results))

      on_iterator_loop_done(frame.run, frame.graph, frame.context, node_id)
      follow_edges(frame, node_id, "done", strict: true)
    end

    def apply_iterator_done_result(frame, node_id, node_data, collection, results)
      frame.context.set_variable("results", results)
      frame.context.current_input = results
      frame.context.store_node_output(node_id, results)
      frame.context.clear_iterator_state(node_id)
      frame.scheduler.complete_active_work_item

      done_vars = { "results" => results, "total" => collection.size }
      done_result = NodeResult.new(status: :success, output: results, variables: done_vars)
      register_node_scoped_variables(frame.context, node_id, node_data, done_result)
    end

    def iterator_done_execution(frame, node_id, node_data, results)
      NodeExecution.new(
        node_id:, node_type: "iterator", status: :success,
        input: safe_serialize(node_input_snapshot("iterator", node_data, frame.context)),
        output: safe_serialize(results), next_port: "done",
        started_at: Time.current, finished_at: Time.current, error: nil,
      )
    end

    def iterator_parallel?(state)
      ActiveModel::Type::Boolean.new.cast(state["parallel"])
    end

    def iterator_parallel_limit(state)
      configured = Integer(state["max_parallel_branches"], exception: false)
      max_parallel_branches = configured if configured&.positive?

      max_parallel_branches || Missions::Nodes::Iterator::DEFAULT_MAX_PARALLEL_BRANCHES
    end

    def iterator_batches(collection_size, start_index, batch_size)
      return [] if start_index >= collection_size

      start_index.step(collection_size - 1, batch_size).map do |batch_start|
        batch_end = [batch_start + batch_size - 1, collection_size - 1].min
        (batch_start..batch_end).to_a
      end
    end

    def halt_iterator_flow?(run, scheduler)
      scheduler.execution_count.value >= self.class::MAX_TOTAL_EXECUTIONS || run.reload.cancelled?
    end
  end
end
