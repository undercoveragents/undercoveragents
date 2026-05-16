# frozen_string_literal: true

module Missions
  module Nodes
    # Control: Loop — repeats downstream nodes while a condition is true or for N iterations.
    class Loop
      include MissionNodePlugin

      MAX_ITERATIONS = 1000
      DESIGNER_INSTRUCTIONS = <<~INSTRUCTIONS.strip.freeze
        ## Loop (type: "loop")
        Repeats downstream nodes while a condition is true or for N iterations.
        Max #{MAX_ITERATIONS} iterations.

        ### Configuration
        ```json
        {
          "condition": "iteration < 5",
          "max_iterations": 10
        }
        ```
        - `condition`: Expression — loop continues while true.
          Supports {{variable}} interpolation. If omitted, loops until max_iterations.
        - `max_iterations`: Safety limit (default #{MAX_ITERATIONS}, max #{MAX_ITERATIONS}).

        ### How It Works
        1. Evaluates condition (if present). If false or max reached → `done` port.
        2. If true → executes nodes connected to `loop` port.
        3. Increments iteration counter and re-evaluates.

        ### Boundary Rules
        - Do not wire a body node back into this loop node. The loop reevaluates internally.
        - Do not mix loop-body inputs with non-body inputs on the same downstream node.
          Route once-per-run continuations through the `done` port when you need post-loop work.
        - Leaving `done` unconnected is acceptable when the loop intentionally ends that nested
          body branch and no post-loop continuation is needed at that level.

        ### Output Ports
        - `loop`: Loop body (connect processing nodes here)
        - `done`: Executed after loop completes

        ### Output Variables
        - `iteration` (number): Current zero-based iteration index [port: loop]
        - `completed` (boolean): True when loop finished [port: done]

        ### Wiring Pattern
        ```
        Loop →[loop]→ Processing → Set Variable (update state) → ...
             →[done]→ Output
        ```
      INSTRUCTIONS

      class << self
        def node_type = "loop"
        def node_label = "Loop"
        def node_icon = "fa-solid fa-arrows-rotate"
        def node_color = "#14b8a6"
        def node_category = :control
        def node_description = "Repeats downstream nodes while a condition is met or for a set number of iterations"

        def field_contracts
          [
            field_contract(
              key: "condition",
              kind: :formula,
              value_type: :string,
              description: "Expression — loop continues while true",
            ),
            field_contract(
              key: "max_iterations",
              value_type: :number,
              description: "Maximum iteration count (default 1000)",
            ),
          ]
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "iteration", type: :number, description: "Current iteration index (zero-based)", port: "loop" },
              { name: "completed", type: :boolean, description: "True when loop has finished", port: "done" },
            ],
          )
        end

        def default_output_ports
          [
            { key: "loop", label: "Loop Body" },
            { key: "done", label: "Completed" },
          ]
        end

        def designer_instructions = DESIGNER_INSTRUCTIONS
      end

      register_node!

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        node_id = context.get_variable("_current_node_id")
        resolver = Missions::ValueResolver.new(context)
        max_count = resolve_max_count(node_data)
        condition = node_data["condition"] || node_data["expression"]
        current_iteration = context.loop_iteration(node_id)

        return max_reached_result(current_iteration) if current_iteration >= max_count
        return check_condition(context, resolver, condition, current_iteration, node_id) if condition.present?

        continue_loop(context, node_id, current_iteration)
      end

      private

      def resolve_max_count(node_data)
        count = (node_data["max_iterations"] || node_data["count"] || MAX_ITERATIONS).to_i
        count.clamp(1, MAX_ITERATIONS)
      end

      def max_reached_result(current_iteration)
        NodeResult.new(
          status: :success,
          output: "Loop completed after #{current_iteration} iterations",
          next_port: "done",
          variables: { "iteration" => current_iteration, "completed" => true },
        )
      end

      def check_condition(context, resolver, condition, current_iteration, node_id)
        rendered = resolver.template(condition)
        result = context.evaluate(rendered)

        return unevaluable_result(condition, current_iteration) if result.nil?
        return condition_false_result(current_iteration) unless result

        continue_loop(context, node_id, current_iteration)
      end

      def unevaluable_result(condition, current_iteration)
        NodeResult.new(
          status: :success,
          output: "Loop condition '#{condition}' could not be evaluated (undefined variables?), exiting loop",
          next_port: "done",
          variables: { "iteration" => current_iteration, "completed" => true },
        )
      end

      def condition_false_result(current_iteration)
        NodeResult.new(
          status: :success,
          output: "Loop condition false after #{current_iteration} iterations",
          next_port: "done",
          variables: { "iteration" => current_iteration, "completed" => true },
        )
      end

      def continue_loop(context, node_id, current_iteration)
        context.set_runtime_variable("iteration", current_iteration)
        context.set_loop_iteration(node_id, current_iteration + 1)

        NodeResult.new(
          status: :success,
          output: current_iteration,
          next_port: "loop",
          variables: { "iteration" => current_iteration },
        )
      end
    end
  end
end
