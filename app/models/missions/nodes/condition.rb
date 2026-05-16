# frozen_string_literal: true

module Missions
  module Nodes
    # Control: Condition — evaluates an expression and branches.
    # Follows "true" port if expression evaluates truthy, "false" port otherwise.
    class Condition
      include MissionNodePlugin

      class << self
        def node_type = "condition"
        def node_label = "Condition"
        def node_icon = "fa-solid fa-code-branch"
        def node_color = "#f97316"
        def node_category = :control
        def node_description = "Branches flow based on a condition expression"

        def field_contracts
          [
            field_contract(
              key: "expression",
              kind: :formula,
              value_type: :string,
              description: "Expression to evaluate",
              required: true,
            ),
          ]
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "result", type: :boolean, description: "Result of the condition evaluation" },
            ],
          )
        end

        def default_output_ports
          [
            { key: "true", label: "True" },
            { key: "false", label: "False" },
          ]
        end

        def mutually_exclusive_output_ports? = true

        def designer_instructions
          <<~INSTRUCTIONS.strip
            ## Condition (type: "condition")
            Evaluates an expression and branches the flow.
            Routes to `true` port when truthy, `false` port when falsy.

            ### Configuration
            ```json
            { "expression": "score > 0.8" }
            ```
            - `expression` (required): Expression supporting `{{variable}}` interpolation.
              Formula operands must resolve to scalars. If `list_node_variables` shows an array or hash,
              derive a scalar upstream before using it here.
            #{Missions::ExpressionDocs::NODE_HINT}

            ### Expression Examples
            - `score > 0.8`, `status == 'approved'`, `count > 0 AND enabled == true`
            - `NOT(is_blocked)`, `DIG(http_request.response_body, 'status') == 'ok'`

            ### Output Ports
            - `true`: Expression evaluated to true
            - `false`: Expression evaluated to false

            ### Runtime Branch Pruning
            - When the condition completes, only the selected port stays enabled.
            - The non-selected port is disabled at runtime.
            - Nodes that only receive disabled incoming edges are disabled too, so downstream joins wait only on the remaining active predecessors.

            ### Output Variables
            - `result` (boolean): The evaluation result
          INSTRUCTIONS
        end
      end

      register_node!

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        expression = node_data["expression"] || node_data["condition"]
        resolver = Missions::ValueResolver.new(context)

        return failure("Condition node has no expression configured") if expression.blank?

        rendered_expression = resolver.template(expression)
        result = context.evaluate(rendered_expression)

        return unevaluable(rendered_expression) if result.nil?

        port = result ? "true" : "false"
        NodeResult.new(status: :success, output: result, next_port: port, variables: { "result" => result })
      end

      private

      def failure(message)
        NodeResult.new(status: :failure, output: message)
      end

      def unevaluable(expression)
        NodeResult.new(
          status: :failure,
          output: "Could not evaluate condition: '#{expression}' — check that all referenced variables are defined",
        )
      end
    end
  end
end
