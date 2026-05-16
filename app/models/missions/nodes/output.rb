# frozen_string_literal: true

module Missions
  module Nodes
    # Output node — defines the mission's return value.
    # Agnostic of invocation method (API, UI, tool) — the mission just declares
    # a return status, optional status code, and output variables or a response body.
    class Output
      include MissionNodePlugin

      VALID_STATUSES = ["success", "error"].freeze
      FIELD_CONTRACT_ATTRIBUTES = [
        { key: "status", kind: :enum, value_type: :string, description: "Return status: success or error" },
        { key: "status_code", value_type: :number, description: "Numeric return code" },
        {
          key: "response_body",
          kind: :template,
          value_type: :string,
          description: "Response body template with {{variable}} interpolation",
        },
        {
          key: "selected_variables",
          kind: :output_selection,
          value_type: :array,
          description: "Qualified variable names to include in output",
        },
      ].freeze
      DESIGNER_INSTRUCTIONS = <<~'INSTRUCTIONS'.strip.freeze
        ## Output (type: "output")
        Terminal node — defines the mission's return value.
        No outgoing edges.

        ### Configuration
        ```json
        {
          "status": "success",
          "status_code": 200,
          "response_body": "{\"result\": \"{{summarize.response}}\"}",
          "selected_variables": ["summarize.response", "extract.score"]
        }
        ```
        - `status`: Return status — `"success"` (default) or `"error"`.
        - `status_code`: Numeric return code (default 200). Use standard HTTP codes as convention (e.g. 200, 400, 500).
        - `response_body`: Optional custom response body template. Supports `{{variable}}` interpolation.
        - `selected_variables`: Array of **qualified** variable names to include in the output.
          Use the format `node_variable_prefix.variable_name` (e.g. `summarize.response`).
          The variable prefix for each node is shown in the `add_node` result and in `read_mission_flow`.
          Duplicate node labels receive numeric suffixes in those prefixes (`json_extract_2`, etc.).
          Call `list_node_variables` with the output node's ID after connecting it to discover
          all available qualified variable names.
          If empty or omitted, passes through the current branch input as the default output.

        ### How to configure selected_variables
        1. Add and connect all upstream nodes first.
        2. Connect the upstream node(s) → output node.
        3. Call `list_node_variables` with this output node's ID to see available qualified names.
        4. Set `selected_variables` to the desired qualified names from that list.

        ### Output Ports
        None (terminal node).
      INSTRUCTIONS

      class << self
        def node_type = "output"
        def node_label = "Output"
        def node_icon = "fa-solid fa-arrow-right-from-bracket"
        def node_color = "#ec4899"
        def node_category = :input_output
        def node_description = "Defines the mission output with status, code, and return data"

        def field_contracts
          FIELD_CONTRACT_ATTRIBUTES.map { |attributes| field_contract(**attributes) }
        end

        def dynamic_output_variables(node_data)
          parse_selected_variables(node_data["selected_variables"]).filter_map do |name|
            next if name.blank?

            {
              name:,
              type: :any,
              description: "Selected output variable",
            }
          end
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "*", type: :any, description: "Dynamic — each selected variable becomes an output" },
              { name: "_output_meta", type: :hash,
                description: "Output metadata (status, status_code, response_body)", },
            ],
          )
        end

        def default_output_ports
          [] # Terminal node — no outgoing edges
        end

        def designer_instructions = DESIGNER_INSTRUCTIONS

        private

        def parse_selected_variables(value)
          case value
          when Array
            value
          when String
            JSON.parse(value)
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

        outputs = collect_outputs(context, node_data)
        meta = build_output_meta(context, node_data)

        outputs["_output_meta"] = meta
        context.set_variable("_output_meta", meta)
        outputs.each { |k, v| context.set_variable(k, v) }

        NodeResult.new(status: :success, output: outputs, variables: outputs)
      rescue ArgumentError
        NodeResult.new(status: :failure, output: "Invalid status code: #{node_data["status_code"]}")
      end

      private

      def collect_outputs(context, node_data)
        selected = node_data["selected_variables"] || []
        outputs = selected.index_with { |name| context.get_variable(name) }
        fallback_output = context.current_input_present? ? context.current_input : context.get_variable("input")
        outputs["output"] = fallback_output if outputs.empty?
        outputs
      end

      def build_output_meta(context, node_data)
        status = resolve_status(node_data)
        meta = { "status" => status, "status_code" => Integer(node_data["status_code"] || 200) }
        body = interpolate_body(context, node_data)
        meta["response_body"] = body if body
        meta
      end

      def resolve_status(node_data)
        raw = node_data["status"].presence || "success"
        VALID_STATUSES.include?(raw) ? raw : "success"
      end

      def interpolate_body(context, node_data)
        return if node_data["response_body"].blank?

        context.interpolate(node_data["response_body"].to_s)
      end
    end
  end
end
