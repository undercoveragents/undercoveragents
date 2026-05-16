# frozen_string_literal: true

module Missions
  module Nodes
    # Control: Switch — evaluates an expression and routes to a matching case port.
    # Each case is a named port. Falls through to "default" if no match.
    class Switch
      include MissionNodePlugin

      DESIGNER_INSTRUCTIONS = <<~INSTRUCTIONS.strip.freeze
        ## Switch (type: "switch")
        Routes flow to different output ports based on an expression's value.

        ### Configuration
        ```json
        {
          "expression": "category",
          "cases": {
            "technical": "technical",
            "billing": "billing",
            "general": "general"
          }
        }
        ```
        - `expression` (required): Expression to evaluate (supports {{variable}} interpolation)
        - `cases`: Map where keys are port names and values are match values

        The expression result is compared to each case value. If matched, flow goes to that port.
        If no match, flow goes to the "default" port.

        ### Output Ports
        - Dynamic ports from case keys (e.g. "technical", "billing")
        - `default`: Fallback when no case matches

        ### Runtime Branch Pruning
        - When the switch completes, only the matched case port or `default` stays enabled.
        - All non-selected case ports are disabled at runtime.
        - Downstream joins ignore those disabled paths and wait only on the remaining active predecessors.

        ### Output Variables
        - `value` (string): The evaluated expression value
        - `matched` (boolean): Whether any case matched
      INSTRUCTIONS

      class << self
        def node_type = "switch"
        def node_label = "Switch"
        def node_icon = "fa-solid fa-arrows-split-up-and-left"
        def node_color = "#e11d48"
        def node_category = :control
        def node_description = "Routes flow to different paths based on a value"

        def field_contracts
          [
            field_contract(
              key: "expression",
              kind: :formula,
              value_type: :string,
              description: "Expression whose value is matched against cases",
              required: true,
            ),
            field_contract(
              key: "cases",
              value_type: :hash,
              description: "Map of port names to match values",
            ),
          ]
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "value", type: :string, description: "Evaluated expression value" },
              { name: "matched", type: :boolean, description: "Whether a case matched" },
            ],
          )
        end

        def default_output_ports
          # Dynamic ports based on configured cases + default
          [
            { key: "default", label: "Default" },
          ]
        end

        def output_ports_for(node_data)
          case_ports(node_data).map { |key| { key:, label: key.to_s.humanize } } + default_output_ports
        end

        # Switch uses dynamic case-based ports at runtime so it must always
        # use strict routing even though it declares only one static port.
        def strict_port_routing? = true

        def mutually_exclusive_output_ports? = true

        def designer_instructions = DESIGNER_INSTRUCTIONS

        private

        def case_ports(node_data)
          cases = node_data["cases"]

          case cases
          when Hash
            cases.keys.map(&:to_s)
          when String
            parsed = JSON.parse(cases)
            parsed.is_a?(Hash) ? parsed.keys.map(&:to_s) : []
          else
            []
          end
        rescue JSON::ParserError
          []
        end
      end

      register_node!

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        expression = node_data["expression"] || ""
        return NodeResult.new(status: :failure, output: "Switch node has no expression configured") if expression.blank?

        switch_result(context, expression, node_data["cases"] || {})
      end

      private

      def switch_result(context, expression, cases)
        resolver = Missions::ValueResolver.new(context)
        value = resolver.formula_or_literal(expression).to_s
        matched_port = cases.find { |_port, case_value| case_value.to_s == value }&.first
        port = matched_port || "default"

        NodeResult.new(
          status: :success, output: value, next_port: port,
          variables: { "value" => value, "matched" => matched_port.present? },
        )
      end
    end
  end
end
