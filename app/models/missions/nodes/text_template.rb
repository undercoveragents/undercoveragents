# frozen_string_literal: true

module Missions
  module Nodes
    # Node: Text Template — composes text using variable interpolation.
    # Supports {{variable}} and {{node_name.variable}} patterns.
    class TextTemplate
      include MissionNodePlugin

      class << self
        def node_type = "text_template"
        def node_label = "Text Template"
        def node_icon = "fa-solid fa-file-lines"
        def node_color = "#7c3aed"
        def node_category = :node
        def node_description = "Composes text using a template with variable interpolation"

        def field_contracts
          [
            field_contract(
              key: "template",
              kind: :template,
              value_type: :string,
              description: "Template text with {{variable}} placeholders",
              required: true,
            ),
          ]
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "text", type: :string, description: "Rendered text output" },
            ],
          )
        end
      end

      register_node!

      def output_ports
        [{ key: "default", label: "Output" }]
      end

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        template = node_data["template"].to_s

        return NodeResult.new(status: :failure, output: "No template provided") if template.blank?

        rendered = context.interpolate(template)
        variables = { "text" => rendered }

        NodeResult.new(status: :success, output: rendered, variables:)
      end
    end
  end
end
