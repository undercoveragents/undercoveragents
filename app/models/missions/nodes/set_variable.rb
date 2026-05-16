# frozen_string_literal: true

module Missions
  module Nodes
    # Control: SetVariable — sets one or more variables using expressions.
    class SetVariable
      include MissionNodePlugin

      DESIGNER_INSTRUCTIONS = <<~INSTRUCTIONS.strip.freeze
        ## Set Variable (type: "set_variable")
        Sets one or more variables using expressions or templates.

        ### Configuration
        ```json
        {
          "assignments": {
            "greeting": "Hello {{user_name}}",
            "total": "price * quantity",
            "status": "active"
          }
        }
        ```
        - `assignments` (required): A hash/object where keys are variable names and values are
          expressions (math/logic) or templates ({{variable}} interpolation).
          Values are first interpolated, then evaluated as expressions.
          If evaluation fails, the literal string is used.
          Formula-style assignments must use scalar operands only. Do not compare typed array/hash
          mission outputs directly, and do not interpolate them into formulas to force a comparison.
          Derive a scalar upstream first.

        Each assignment key becomes a variable accessible downstream.

        ### Output Ports
        - `default`: Output
      INSTRUCTIONS

      class << self
        def node_type = "set_variable"
        def node_label = "Set Variable"
        def node_icon = "fa-solid fa-equals"
        def node_color = "#84cc16"
        def node_category = :control
        def node_description = "Sets variables for downstream nodes"

        def field_contracts
          [
            field_contract(
              key: "assignments",
              kind: :assignment_map,
              value_type: :hash,
              description: "Map of variable names to expressions",
              required: true,
            ),
          ]
        end

        def dynamic_output_variables(node_data)
          parse_assignments(node_data["assignments"]).keys.filter_map do |name|
            next if name.blank?

            {
              name:,
              type: :any,
              description: "Assigned variable",
            }
          end
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "*", type: :any, description: "Dynamic — each assignment key becomes an output variable" },
            ],
          )
        end

        def designer_instructions = DESIGNER_INSTRUCTIONS

        private

        def parse_assignments(assignments)
          case assignments
          when Hash
            assignments
          when String
            JSON.parse(assignments)
          else
            {}
          end
        rescue JSON::ParserError
          {}
        end
      end

      register_node!

      def output_ports
        [{ key: "default", label: "Output" }]
      end

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        assignments = node_data["assignments"] || {}
        resolver = Missions::ValueResolver.new(context)

        result_vars = {}
        assignments.each do |name, expression|
          final = resolver.formula_or_literal(expression)
          context.set_variable(name, final)
          result_vars[name] = final
        end

        NodeResult.new(
          status: :success,
          output: result_vars,
          variables: result_vars,
        )
      end
    end
  end
end
