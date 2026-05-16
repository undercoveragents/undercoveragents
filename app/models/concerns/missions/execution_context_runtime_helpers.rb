# frozen_string_literal: true

module Missions
  module ExecutionContextRuntimeHelpers
    CURRENT_INPUT_KEY = "_current_input_payload"
    TRANSIENT_NODE_VARIABLES = ["_current_node_id", "_current_node_type", "_current_node_data"].freeze
    RUNTIME_HELPER_VARIABLES = [
      *TRANSIENT_NODE_VARIABLES,
      "item",
      "index",
      "total",
      "iteration",
      "_iterator_states",
      "_loop_iterations",
      "_loop_iteration",
    ].freeze
    EXPORTED_RUNTIME_VARIABLES = [].freeze
    TASK_TRANSIENT_STATE_IVAR = :@mission_execution_context_transient_state

    def initialize_runtime_helpers
      @transient_state = {}
    end

    def set_runtime_variable(name, value, persist: false)
      key = normalize_key(name)
      transient_state_for_current_task[key] = value
      persist_variable(key, value) if persist
      value
    end

    def current_input=(value)
      transient_state_for_current_task[CURRENT_INPUT_KEY] = value
    end

    def current_input
      transient_state_for_current_task[CURRENT_INPUT_KEY]
    end

    def current_input_present?
      transient_state_for_current_task.key?(CURRENT_INPUT_KEY)
    end

    def clear_current_input
      transient_state_for_current_task.delete(CURRENT_INPUT_KEY)
    end

    def clear_runtime_variable(name)
      transient_state_for_current_task.delete(normalize_key(name))
    end

    def runtime_variable_set?(name)
      transient_state_for_current_task.key?(normalize_key(name))
    end

    def snapshot_runtime_state
      transient_state_for_current_task.deep_dup
    end

    def inherit_runtime_state(state)
      runtime_state = state ? state.deep_dup : {}
      task = current_async_task
      return @transient_state = runtime_state unless task

      runtime_state_store(task)[self] = runtime_state
    end

    def iterator_state(node_id)
      return {} if node_id.blank?

      iterator_states[node_id.to_s] || {}
    end

    def set_iterator_state(node_id, **attributes)
      return {} if node_id.blank?

      states = iterator_states.deep_dup
      state = (states[node_id.to_s] ||= {})
      attributes.each do |key, value|
        state[key.to_s] = value
      end

      set_runtime_variable("_iterator_states", states)
      state
    end

    def clear_iterator_state(node_id)
      return if node_id.blank? || iterator_states.empty?

      states = iterator_states.deep_dup
      states.delete(node_id.to_s)
      set_runtime_variable("_iterator_states", states)
    end

    def loop_iteration(node_id = nil, fallback: 0)
      if node_id.present?
        stored = loop_iterations[node_id.to_s]
        return stored.to_i unless stored.nil?

        return fallback.to_i
      end

      stored = get_variable("_loop_iteration")
      return stored.to_i unless stored.nil?

      fallback.to_i
    end

    def set_loop_iteration(node_id, value)
      normalized_value = value.to_i

      if node_id.present?
        states = loop_iterations.deep_dup
        states[node_id.to_s] = normalized_value
        set_runtime_variable("_loop_iterations", states)
      end

      set_runtime_variable("_loop_iteration", normalized_value)
      normalized_value
    end

    def clear_loop_iteration(node_id)
      if node_id.present?
        states = loop_iterations.deep_dup
        states.delete(node_id.to_s)

        if states.empty?
          clear_runtime_variable("_loop_iterations")
        else
          set_runtime_variable("_loop_iterations", states)
        end
      end

      clear_runtime_variable("_loop_iteration")
    end

    def clear_runtime_state_for_current_task
      task = current_async_task
      return @transient_state.clear unless task

      task.instance_variable_get(TASK_TRANSIENT_STATE_IVAR)&.delete(self)
    end

    private

    def transient_node_variable?(name)
      TRANSIENT_NODE_VARIABLES.include?(name.to_s)
    end

    def runtime_helper_variable?(name)
      RUNTIME_HELPER_VARIABLES.include?(name.to_s)
    end

    def exported_runtime_variables
      transient_state_for_current_task.slice(*EXPORTED_RUNTIME_VARIABLES)
    end

    def runtime_expression_variables
      transient_state_for_current_task.slice(*RUNTIME_HELPER_VARIABLES)
    end

    def transient_state_for_current_task
      task = current_async_task
      return @transient_state unless task

      task_state = runtime_state_store(task)
      task_state.fetch(self) { task_state[self] = {} }
    end

    def runtime_state_store(task)
      task.instance_variable_get(TASK_TRANSIENT_STATE_IVAR) || begin
        {}.compare_by_identity.tap do |store|
          task.instance_variable_set(TASK_TRANSIENT_STATE_IVAR, store)
        end
      end
    end

    def iterator_states
      states = transient_state_for_current_task["_iterator_states"]
      states.is_a?(Hash) ? states : {}
    end

    def loop_iterations
      states = transient_state_for_current_task["_loop_iterations"]
      states.is_a?(Hash) ? states : {}
    end

    def current_async_task
      return unless defined?(Async::Task)

      Async::Task.current
    rescue RuntimeError
      nil
    end
  end
end
