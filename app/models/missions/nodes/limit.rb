# frozen_string_literal: true

module Missions
  module Nodes
    # Control: Limit — takes or skips items from an array.
    # Returns a subset of the collection from a given offset up to a count.
    class Limit
      include MissionNodePlugin
      include Missions::CollectionResolver

      FIELD_CONTRACT_ATTRIBUTES = [
        {
          key: "collection",
          kind: :collection_ref,
          value_type: :array,
          description: "Array to limit",
          required: true,
        },
        {
          key: "count",
          kind: :formula,
          value_type: :number,
          description: "Maximum number of items to take",
          required: true,
        },
        {
          key: "offset",
          kind: :formula,
          value_type: :number,
          description: "Number of items to skip from the start",
        },
      ].freeze

      class << self
        def node_type = "limit"
        def node_label = "Limit"
        def node_icon = "fa-solid fa-scissors"
        def node_color = "#ca8a04"
        def node_category = :control
        def node_description = "Takes a subset of items from an array"

        def field_contracts
          FIELD_CONTRACT_ATTRIBUTES.map { |attributes| field_contract(**attributes) }
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "items", type: :array, description: "Resulting subset of items" },
              { name: "count", type: :number, description: "Number of items returned" },
              { name: "total", type: :number, description: "Total items in original collection" },
            ],
          )
        end
      end

      register_node!

      MAX_ITEMS = 10_000

      def output_ports
        [{ key: "default", label: "Output" }]
      end

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        collection_expr = node_data["collection"].to_s
        count = resolve_integer(context, node_data["count"].to_s, "count")
        offset = resolve_integer(context, node_data["offset"].to_s, "offset") || 0

        error = validate_execute_inputs(collection_expr, count, offset)
        return error if error

        collection = resolve_and_validate_collection(context, collection_expr)
        return collection if collection.is_a?(NodeResult)

        items = collection.drop(offset).take(count)

        variables = { "items" => items, "count" => items.size, "total" => collection.size }
        NodeResult.new(status: :success, output: "#{items.size} of #{collection.size} items", variables:)
      end

      private

      def validate_execute_inputs(collection_expr, count, offset)
        return NodeResult.new(status: :failure, output: "No collection configured") if collection_expr.blank?
        return count if count.is_a?(NodeResult)
        return offset if offset.is_a?(NodeResult)

        nil
      end

      def resolve_and_validate_collection(context, expr)
        collection = resolve_collection_reference(context, expr)
        return NodeResult.new(status: :failure, output: "Collection must be an array") unless collection.is_a?(Array)
        if collection.size > MAX_ITEMS
          return NodeResult.new(status: :failure,
                                output: "Collection exceeds maximum of #{MAX_ITEMS}",)
        end

        collection
      end

      def resolve_integer(context, raw, label)
        return nil if raw.blank?

        interpolated = context.interpolate(raw)
        evaluated = context.evaluate(interpolated)
        value = Integer(evaluated.nil? ? interpolated : evaluated)
        return NodeResult.new(status: :failure, output: "#{label.capitalize} must be positive") if value.negative?

        value
      rescue ArgumentError, TypeError
        NodeResult.new(status: :failure, output: "Invalid #{label}: #{raw}")
      end
    end
  end
end
