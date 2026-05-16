# frozen_string_literal: true

module Missions
  module Nodes
    # Node: JSON Extract — parses a JSON string and extracts values by path.
    class JsonExtract
      include MissionNodePlugin

      DESIGNER_INSTRUCTIONS = <<~INSTRUCTIONS.strip.freeze
        ## JSON Extract (type: "json_extract")
        Parses a JSON string, object, or root array and extracts values using dot-notation paths.
        Prefer this over `code` when the job is to parse API JSON, pull nested fields, select array
        elements, or pass a nested subobject downstream.

        ### Configuration
        ```json
        {
          "source": "{{node.variable}}",
          "extractions": {
            "user_name": "data.user.name",
            "email": "data.user.email",
            "first_item": "data.items.0.title"
          }
        }
        ```
        - `source` (required): JSON string or template-valued variable reference to parse. Supports root objects and root arrays.
          When you want an upstream mission variable here, wrap the exact identifier from
          `list_node_variables` in `{{...}}` (for example `{{node.variable}}`).
          A bare `node.variable` is literal text, not a variable lookup.
        - `extractions`: Map of output variable names to dot-notation paths.
          Supports nested objects (`data.user.name`) and array indices (`items.0`).
          Treat it like a pragmatic JSON `dig`: use dot-separated keys plus numeric positions when
          you need one nested value such as `data.items.0.title`, `results.2.id`, or `0.id` for a
          root array. Use a bare numeric segment like `0` when you want the full first array item.

        ### Output Ports
        - `default`: Output

        ### Output Variables
        - `parsed` (any): The full parsed JSON value (object or array)
        - Each extraction key becomes a named variable, including nested hashes or arrays when the path stops there
        - The node instance prefix is unique per flow. If multiple JSON Extract nodes share the
          same label, later ones receive suffixed prefixes such as `json_extract_2`.
          Use `list_node_variables` or expanded `read_mission_flow` for exact qualified names.
      INSTRUCTIONS

      class << self
        def node_type = "json_extract"
        def node_label = "JSON Extract"
        def node_icon = "fa-solid fa-file-code"
        def node_color = "#059669"
        def node_category = :node
        def node_description = "Parses JSON objects or arrays and extracts nested values by path"

        def field_contracts
          [
            field_contract(
              key: "source",
              kind: :template,
              value_type: :string,
              description: "JSON string or variable name to parse",
              required: true,
            ),
            field_contract(
              key: "extractions",
              value_type: :hash,
              description: "Named paths to extract (key: name, value: JSON path)",
            ),
          ]
        end

        def dynamic_output_variables(node_data)
          parse_extractions(node_data["extractions"]).keys.filter_map do |name|
            next if name.blank?

            {
              name:,
              type: :any,
              description: "Extracted JSON value",
            }
          end
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "parsed", type: :any, description: "Full parsed JSON value (object or array)" },
              { name: "*", type: :any, description: "Dynamic — each extraction becomes a named output" },
            ],
          )
        end

        def designer_instructions = DESIGNER_INSTRUCTIONS

        private

        def parse_extractions(extractions)
          case extractions
          when Hash
            extractions
          when String
            JSON.parse(extractions)
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
        source = context.interpolate(node_data["source"].to_s)
        extractions = node_data["extractions"] || {}

        return NodeResult.new(status: :failure, output: "No JSON source provided") if source.blank?

        parsed = parse_json(source)
        return NodeResult.new(status: :failure, output: "Invalid JSON: could not parse source") if parsed.nil?

        variables = { "parsed" => parsed }
        extract_paths(parsed, extractions, variables)

        NodeResult.new(status: :success, output: parsed.to_s, variables:)
      end

      def validate_config!(node_data = {})
        source = node_data["source"]
        return if source.blank?
        return if valid_json_literal?(source)
        return if template_reference?(source)

        raise ArgumentError,
              "source must be valid JSON or a {{variable}} template reference; plain strings are not allowed"
      end

      private

      def parse_json(source)
        JSON.parse(source)
      rescue JSON::ParserError
        nil
      end

      def valid_json_literal?(source)
        JSON.parse(source)
        true
      rescue JSON::ParserError
        false
      end

      def template_reference?(source)
        source.is_a?(String) && source.match?(/\{\{[^}]+\}\}/)
      end

      def extract_paths(parsed, extractions, variables)
        extractions.each do |name, path|
          variables[name.to_s] = dig_path(parsed, path.to_s)
        end
      end

      def dig_path(obj, path)
        return obj if path.blank?

        segments = path.split(".").map { |s| integer?(s) ? s.to_i : s }
        segments.reduce(obj) do |current, segment|
          case current
          when Hash then current[segment.to_s]
          when Array then current[segment]
          end
        end
      end

      def integer?(str)
        str.match?(/\A\d+\z/)
      end
    end
  end
end
