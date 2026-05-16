# frozen_string_literal: true

module Missions
  # Node handler invocation, execution logging, and output registration.
  module RunnerNodeExecution
    private

    def execute_single_node(request)
      request.execution_count.increment
      request.context.execution_count_value = request.execution_count.value
      handler = resolve_handler(request.node_type)
      input_snapshot = node_input_snapshot(request.node_type, request.node_data, request.context)

      started_at = Time.current
      result = execute_node_handler(handler, request)
      finished_at = Time.current

      log_node_execution(request, result, input_snapshot, started_at, finished_at)
      apply_node_result(request, result)
      handle_node_result!(request, result)

      result
    end

    def execute_node_handler(handler, request)
      Timeout.timeout(
        self.class::NODE_EXECUTION_TIMEOUT,
        Missions::ExecutionError,
        "Node '#{request.node_id}' (#{request.node_type}) timed out after #{self.class::NODE_EXECUTION_TIMEOUT}s",
      ) do
        handler.execute(request.context)
      end
    end

    def log_node_execution(request, result, input_snapshot, started_at, finished_at)
      request.context.log_execution(
        NodeExecution.new(
          node_id: request.node_id,
          node_type: request.node_type,
          status: result.status,
          input: safe_serialize(input_snapshot),
          output: safe_serialize(result.output),
          next_port: result.next_port,
          started_at:,
          finished_at:,
          error: result.failure? ? result.output.to_s : nil,
        ),
      )
    end

    def apply_node_result(request, result)
      result.variables.each { |key, value| request.context.set_variable(key, value) }
      register_node_scoped_variables(request.context, request.node_id, request.node_data, result)
      request.context.store_node_output(request.node_id, result.output)
      request.context.current_input = result.output
      request.scheduler.complete_active_work_item unless result.failure?
      persist_state(request.run, request.context, current_node_id: request.node_id)
    end

    def handle_node_result!(request, result)
      if result.failure?
        raise ExecutionError, "Node '#{request.node_id}' (#{request.node_type}) failed: #{result.output}"
      end

      return unless request.node_type == "output"

      raise OutputReached.new(node_id: request.node_id, output_variables: result.variables)
    end

    def skip_disabled_node(frame, node_id, node_type)
      execution = NodeExecution.new(
        node_id:,
        node_type:,
        status: :skip,
        input: nil,
        output: "Skipped (disabled)",
        next_port: nil,
        started_at: Time.current,
        finished_at: Time.current,
        error: nil,
      )
      frame.context.log_execution(execution)
      frame.scheduler.complete_active_work_item
      persist_state(frame.run, frame.context, current_node_id: node_id)

      follow_edges(frame, node_id, nil, strict: false)
    end

    def resolve_handler(node_type)
      klass = MissionNodePlugin.resolve(node_type)
      raise NodeNotFoundError, "Unknown node type '#{node_type}'" unless klass

      klass.new
    end

    def multi_port_node?(node_type)
      klass = MissionNodePlugin.resolve(node_type)
      return false unless klass

      klass.strict_port_routing?
    end

    def register_node_scoped_variables(context, node_id, node_data, result)
      node_name = derive_node_name(context, node_data, node_id)
      return if node_name.blank? || result.variables.blank?

      context.set_node_variables(node_name, result.variables)
    end

    def derive_node_name(context, node_data, node_id)
      flow_data = context.mission_run.flow_snapshot.presence || context.mission_run.mission&.flow_data || {}

      Missions::NodeVariableNameResolver.for_node(node_id, flow_data) ||
        Missions::NodeVariableNameResolver.base_name(node_data, node_id)
    end

    def safe_serialize(value)
      case value
      when String, Numeric, TrueClass, FalseClass, NilClass
        value
      when Array
        value.map { |nested_value| safe_serialize(nested_value) }
      when Hash
        value.transform_values { |nested_value| safe_serialize(nested_value) }
      else
        value.to_s
      end
    end

    def node_input_snapshot(node_type, node_data, context)
      Missions::NodeInputSnapshot.new(node_type:, node_data:, context:).call
    end
  end
end
