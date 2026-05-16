# frozen_string_literal: true

module Missions
  module Nodes
    # Node: Aggregate — reduces an array to a single value using an operation.
    # Supports sum, count, average, min, max, first, last, join, collect.
    class Aggregate
      include MissionNodePlugin
      include Missions::CollectionResolver

      OPERATIONS = ["sum", "count", "average", "min", "max", "first", "last", "join", "collect"].freeze
      MAX_ITEMS = 10_000
      DESIGNER_INSTRUCTIONS = <<~INSTRUCTIONS.strip.freeze
        ## Aggregate (type: "aggregate")
        Reduces an array to a single value. Commonly used after an iterator.

        ### Configuration
        ```json
        {
          "collection": "results",
          "operation": "join",
          "field": "name"
        }
        ```
        - `collection` (required): Variable name containing the array
        - `operation` (required): One of: #{OPERATIONS.join(", ")}
        - `field`: For arrays of objects, the field to aggregate on

        ### Operations
        - `sum`, `average`, `min`, `max` — numeric operations
        - `count` — returns the number of items in the collection; it does not count semantic matches
        - `first`, `last` — returns first/last item
        - `join` — concatenates values with ", "
        - `collect` — compacts non-nil values

        If you need to count a subset such as even numbers, filter the collection first
        (for example `filter_evens.matches`) or aggregate a filtered iterator result collection.

        ### Output Ports
        - `default`: Output

        ### Output Variables
        - `result` (any): The aggregation result
        - `count` (number): Number of items processed
      INSTRUCTIONS

      class << self
        def node_type = "aggregate"
        def node_label = "Aggregate"
        def node_icon = "fa-solid fa-calculator"
        def node_color = "#7c3aed"
        def node_category = :control
        def node_description = "Reduces an array using an aggregation operation"

        def field_contracts
          [
            field_contract(
              key: "collection",
              kind: :collection_ref,
              value_type: :array,
              description: "Array to aggregate",
              required: true,
            ),
            field_contract(
              key: "operation",
              value_type: :string,
              description: "Aggregation operation",
              required: true,
            ),
            field_contract(
              key: "field",
              value_type: :string,
              description: "Field to aggregate (for arrays of objects)",
            ),
          ]
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "result", type: :any, description: "Aggregation result" },
              { name: "count", type: :number, description: "Number of items processed" },
            ],
          )
        end

        def designer_instructions = DESIGNER_INSTRUCTIONS
      end

      register_node!

      OPERATION_HANDLERS = {
        "sum" => ->(values) { Aggregate.numeric_values(values).sum },
        "count" => ->(values) { values.size },
        "average" => lambda { |values|
          nv = Aggregate.numeric_values(values)
          nv.empty? ? 0 : nv.sum.to_f / nv.size
        },
        "min" => ->(values) { Aggregate.numeric_values(values).min },
        "max" => ->(values) { Aggregate.numeric_values(values).max },
        "first" => ->(values) { values.first },
        "last" => ->(values) { values.last },
        "join" => ->(values) { values.join(", ") },
        "collect" => ->(values) { values.compact },
      }.freeze

      def self.numeric_values(values)
        values.filter_map { |value| numeric_value(value) }
      end

      def self.numeric_value(value)
        return value if value.is_a?(Numeric)

        Float(value)
      rescue ArgumentError, TypeError
        nil
      end

      def output_ports
        [{ key: "default", label: "Output" }]
      end

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        collection_expr = node_data["collection"].to_s
        operation = node_data["operation"].to_s
        field = node_data["field"].to_s.presence

        error = validate_inputs(collection_expr, operation)
        return error if error

        collection = resolve_collection_reference(context, collection_expr)
        return NodeResult.new(status: :failure, output: "Collection must be an array") unless collection.is_a?(Array)
        if collection.size > MAX_ITEMS
          return NodeResult.new(status: :failure,
                                output: "Collection exceeds maximum of #{MAX_ITEMS}",)
        end

        values = field ? collection.map { |item| extract_field(item, field) } : collection
        result = perform_operation(operation, values)

        variables = { "result" => result, "count" => collection.size }
        NodeResult.new(status: :success, output: result.to_s, variables:)
      end

      private

      def validate_inputs(collection_expr, operation)
        return NodeResult.new(status: :failure, output: "No collection configured") if collection_expr.blank?
        return NodeResult.new(status: :failure, output: "No operation configured") if operation.blank?
        return if OPERATIONS.include?(operation)

        NodeResult.new(status: :failure, output: "Unknown operation: #{operation}")
      end

      def extract_field(item, field)
        case item
        when Hash then item[field] || item[field.to_sym]
        else item
        end
      end

      def perform_operation(operation, values)
        OPERATION_HANDLERS[operation]&.call(values)
      end
    end
  end
end
