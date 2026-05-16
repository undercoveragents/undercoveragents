# frozen_string_literal: true

module Missions
  module Nodes
    module InputSupport
      FIELD_TYPES = [
        "string", "string_array",
        "number", "number_array",
        "boolean", "boolean_array",
        "file", "file_array",
        "json",
        "date", "date_array",
        "datetime", "datetime_array",
      ].freeze

      COERCERS = {
        "number" => ->(value) { value.is_a?(Numeric) ? value : value.to_f },
        "number_array" => ->(value) { Array(value).map { |item| item.is_a?(Numeric) ? item : item.to_f } },
        "boolean" => ->(value) { ActiveModel::Type::Boolean.new.cast(value) },
        "boolean_array" => ->(value) { Array(value).map { |item| ActiveModel::Type::Boolean.new.cast(item) } },
        "string_array" => ->(value) { Array(value).map(&:to_s) },
        "date_array" => ->(value) { Array(value).map(&:to_s) },
        "datetime_array" => ->(value) { Array(value).map(&:to_s) },
        "file_array" => ->(value) { Array(value) },
        "json" => ->(value) { value.is_a?(String) ? JSON.parse(value) : value },
      }.freeze

      def self.designer_instructions
        <<~INSTRUCTIONS.strip
          ## Input (type: "input")
          Receives input fields from an API call trigger. Singleton — only one per mission.

          ### Configuration
          Use `variable_name` and `field_type` exactly. Do not use `name` or `type`.
          The `fields` config is an array of field definitions:
          ```json
          {
            "fields": [
              {"variable_name": "user_query", "field_type": "string", "required": true},
              {"variable_name": "max_results", "field_type": "number", "required": false,
               "config": {"default_value": 10}},
              {"variable_name": "tags", "field_type": "string_array", "required": false}
            ]
          }
          ```

          ### Available field_type values
          #{FIELD_TYPES.map { |type| "- `#{type}`" }.join("\n")}

          ### Optional per-field config
          - `config.default_value`: used when the trigger data omits that field.
            Prefer this when the mission must run deterministically without user-provided inputs.

          Each field becomes an output variable accessible downstream as `{{variable_name}}`.
          If no fields are configured, the raw `input` variable is passed through.

          ### Output Ports
          - `default`: Output
        INSTRUCTIONS
      end
    end

    class Input
      include MissionNodePlugin

      FIELD_TYPES = InputSupport::FIELD_TYPES
      COERCERS = InputSupport::COERCERS

      class << self
        def node_type = "input"
        def node_label = "Input"
        def node_icon = "fa-solid fa-right-to-bracket"
        def node_color = "#10b981"
        def node_category = :input_output
        def node_description = "Receives input fields from an API call"
        delegate :designer_instructions, to: InputSupport

        def field_contracts
          [
            field_contract(
              key: "fields",
              kind: :input_fields,
              value_type: :array,
              description: "Array of trigger field definitions",
            ),
          ]
        end

        def singleton?
          true
        end

        def dynamic_output_variables(node_data)
          parse_fields(node_data["fields"]).filter_map do |field|
            name = field["variable_name"].presence
            next unless name

            {
              name:,
              type: dynamic_field_type(field["field_type"]),
              description: field["label"].presence || "Input field",
            }
          end
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "*", type: :any, description: "Dynamic — each field becomes an output variable" },
            ],
          )
        end

        private

        def parse_fields(fields)
          case fields
          when Array
            fields
          when String
            JSON.parse(fields)
          else
            []
          end
        rescue JSON::ParserError
          []
        end

        def dynamic_field_type(field_type)
          case field_type.to_s
          when "number" then :number
          when "boolean" then :boolean
          when "file", "json" then :hash
          when /_array\z/ then :array
          else :string
          end
        end
      end

      register_node!

      def output_ports = [{ key: "default", label: "Output" }]

      def validate_config!(node_data = {})
        raw_fields = node_data["fields"]
        fields = parsed_fields_for_validation(raw_fields)
        raise ArgumentError, "fields must be an array of input field definitions" if raw_fields.present? && fields.nil?

        issues = fields.to_a.flat_map.with_index do |field, index|
          validate_field_definition(field, index)
        end

        raise ArgumentError, issues.join(" ") if issues.any?
      end

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        fields = node_data["fields"] || []
        trigger_data = context.get_variable("_trigger_data") || {}

        if fields.empty?
          # No fields configured — pass through the input variable
          input_value = context.get_variable("input")
          return NodeResult.new(status: :success, output: input_value, variables: { "input" => input_value })
        end

        resolve_fields(fields, trigger_data, context)
      end

      private

      def parsed_fields_for_validation(fields)
        case fields
        when nil
          []
        when Array
          fields
        when String
          parsed = JSON.parse(fields)
          parsed.is_a?(Array) ? parsed : nil
        end
      rescue JSON::ParserError
        nil
      end

      def validate_field_definition(field, index)
        return ["fields[#{index}] must be an object"] unless field.is_a?(Hash)

        issues = []
        variable_name = field["variable_name"].to_s
        field_type = field["field_type"].to_s

        if variable_name.blank?
          hint = field["name"].present? ? " Use `variable_name`, not `name`." : ""
          issues << "fields[#{index}].variable_name is required.#{hint}"
        end

        if field_type.blank?
          hint = field["type"].present? ? " Use `field_type`, not `type`." : ""
          issues << "fields[#{index}].field_type is required.#{hint}"
        elsif FIELD_TYPES.exclude?(field_type)
          issues << "fields[#{index}].field_type must be one of: #{FIELD_TYPES.join(", ")}"
        end

        issues
      end

      def resolve_fields(fields, trigger_data, context)
        variables = {}

        fields.each do |field|
          result = resolve_single_field(field, trigger_data, context, variables)
          return result if result&.failure?
        end

        NodeResult.new(status: :success, output: variables, variables:)
      end

      def resolve_single_field(field, trigger_data, context, variables)
        name = field["variable_name"]
        return nil if name.blank?

        value = resolve_value(field, trigger_data)

        if field["required"] && value.nil?
          return NodeResult.new(status: :failure, output: "Required field '#{name}' is missing")
        end

        value = coerce_value(value, field["field_type"])
        variables[name] = value
        context.set_variable(name, value)
        nil
      end

      def resolve_value(field, trigger_data)
        value = trigger_data[field["variable_name"]]
        value = field.dig("config", "default_value") if value.nil? && field.dig("config", "default_value").present?
        value
      end

      def coerce_value(value, field_type)
        return value if value.nil?

        coercer = COERCERS[field_type]
        coercer ? coercer.call(value) : value
      rescue JSON::ParserError
        value
      end
    end
  end
end
