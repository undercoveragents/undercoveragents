# frozen_string_literal: true

module Missions
  # Mutable execution context passed to every node during a run.
  # Stores execution state, evaluates formulas, and tracks node outputs,
  # edge states, and multi-input join barriers.
  #
  # Supports dot-syntax: +node_name.variable_name+ resolves a variable scoped to
  # a specific node (e.g. +summarizer.llm_response+).
  class ExecutionContext
    include ExecutionContextSchedulerState
    include ExecutionContextRuntimeHelpers
    include ExecutionContextValueStore

    TRANSIENT_NODE_VARIABLES = ExecutionContextRuntimeHelpers::TRANSIENT_NODE_VARIABLES
    RUNTIME_HELPER_VARIABLES = ExecutionContextRuntimeHelpers::RUNTIME_HELPER_VARIABLES
    EXPORTED_RUNTIME_VARIABLES = ExecutionContextRuntimeHelpers::EXPORTED_RUNTIME_VARIABLES
    TASK_TRANSIENT_STATE_IVAR = ExecutionContextRuntimeHelpers::TASK_TRANSIENT_STATE_IVAR

    attr_reader(
      :mission_run,
      :execution_log,
      :node_variables,
      :node_outputs,
      :edge_states,
      :node_arrivals,
      :node_states,
      :calculator,
    )

    delegate :id, to: :mission_run, prefix: true

    def self.restore(mission_run:, state:)
      ctx = new(mission_run:)
      ctx.restore_from(state)
      restore_state_hash(ctx, :@node_outputs, state["node_outputs"])
      restore_state_hash(ctx, :@edge_states, state["edge_states"], &:to_s)
      restore_state_hash(ctx, :@node_arrivals, state["node_arrivals"]) do |value|
        Array(value).map(&:to_s)
      end
      restore_state_hash(ctx, :@node_states, state["node_states"]) do |value|
        value.to_h.transform_keys(&:to_s)
      end
      restore_state_hash(ctx, :@scheduler_frontiers, state["scheduler_frontiers"])
      ctx.execution_count_value = state["execution_count"]
      restore_execution_log(ctx, state)
      ctx
    end

    def self.restore_state_hash(ctx, ivar_name, state_hash)
      target = ctx.instance_variable_get(ivar_name)

      (state_hash || {}).each do |key, value|
        target[key] = block_given? ? yield(value) : value
      end
    end

    def initialize(mission_run:, variables: {})
      @mission_run = mission_run
      initialize_value_store
      @node_outputs = {}
      @edge_states = {}
      @node_arrivals = {}
      @node_states = {}
      @execution_log = []
      initialize_scheduler_state
      initialize_runtime_helpers

      variables.each { |k, v| set_variable(k, v) }
    end
    # ── Node Output Tracking ──

    def store_node_output(node_id, output)
      @node_outputs[node_id.to_s] = output
    end

    def get_node_output(node_id)
      @node_outputs[node_id.to_s]
    end
    # ── Edge State Tracking ──

    def set_edge_state(edge_id, state)
      @edge_states[edge_id.to_s] = state.to_s
    end

    def get_edge_state(edge_id)
      @edge_states[edge_id.to_s]
    end

    def clear_edge_state(edge_id)
      @edge_states.delete(edge_id.to_s)
    end

    # -- Runtime Node State Tracking --

    def set_node_state(node_id, state, **attributes)
      @node_states[node_id.to_s] = {
        "status" => state.to_s,
      }.merge(attributes.compact.transform_keys(&:to_s))
    end

    def get_node_state(node_id)
      @node_states[node_id.to_s]
    end

    def clear_node_state(node_id)
      @node_states.delete(node_id.to_s)
    end

    # -- Join Barrier Tracking --

    def record_node_arrival(node_id, predecessor_id)
      return if node_id.blank? || predecessor_id.blank?

      arrivals = (@node_arrivals[node_id.to_s] ||= [])
      edge_key = predecessor_id.to_s
      arrivals << edge_key unless arrivals.include?(edge_key)
    end

    def node_arrivals_for(node_id)
      Array(@node_arrivals[node_id.to_s])
    end

    def clear_node_arrivals(node_id)
      @node_arrivals.delete(node_id.to_s)
    end

    # ── Execution Logging ──

    def log_execution(node_execution)
      @execution_log << node_execution
    end

    # ── Serialization (for pause/resume) ──

    def to_h
      {
        "variables" => @variables.transform_keys(&:to_s),
        "node_variables" => serialized_node_variables,
        "node_outputs" => serialized_hash(@node_outputs),
        "edge_states" => serialized_hash(@edge_states),
        "node_arrivals" => serialized_hash(@node_arrivals),
        "node_states" => serialized_hash(@node_states),
        "scheduler_frontiers" => serialized_scheduler_frontiers,
        "execution_count" => @execution_count_value,
        "execution_log" => serialized_execution_log,
      }
    end

    private_class_method def self.restore_execution_log(ctx, state)
      (state["execution_log"] || []).each do |entry|
        ctx.log_execution(execution_from_h(entry))
      end
    end

    private

    def serialized_hash(value)
      value.transform_keys(&:to_s)
    end

    def serialized_execution_log
      @execution_log.map { |entry| execution_to_h(entry) }
    end

    def execution_to_h(exec)
      {
        "node_id" => exec.node_id,
        "node_type" => exec.node_type,
        "status" => exec.status.to_s,
        "input" => exec.input,
        "output" => exec.output,
        "next_port" => exec.next_port,
        "started_at" => exec.started_at&.iso8601(3),
        "finished_at" => exec.finished_at&.iso8601(3),
        "error" => exec.error,
      }
    end

    private_class_method def self.execution_from_h(hash)
      Missions::NodeExecution.new(
        node_id: hash["node_id"],
        node_type: hash["node_type"],
        status: hash["status"]&.to_sym,
        input: hash["input"],
        output: hash["output"],
        next_port: hash["next_port"],
        started_at: hash["started_at"] ? Time.iso8601(hash["started_at"]) : nil,
        finished_at: hash["finished_at"] ? Time.iso8601(hash["finished_at"]) : nil,
        error: hash["error"],
      )
    end

    private_class_method :restore_state_hash

    class << self
      def json_dig(json, *keys)
        data = json.is_a?(String) ? JSON.parse(json) : JSON.parse(json.to_json)
        normalized_keys = keys.map { |key| key.is_a?(Numeric) ? key.to_i : key.to_s }
        data.dig(*normalized_keys)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
