# frozen_string_literal: true

module Missions
  module Nodes
    # Control: Sort — sorts an array by value or by a field in objects.
    class Sort
      include MissionNodePlugin
      include Missions::CollectionResolver

      class << self
        def node_type = "sort"
        def node_label = "Sort"
        def node_icon = "fa-solid fa-arrow-down-a-z"
        def node_color = "#2563eb"
        def node_category = :control
        def node_description = "Sorts an array in ascending or descending order"

        def field_contracts
          [
            field_contract(
              key: "collection",
              kind: :collection_ref,
              value_type: :array,
              description: "Array to sort",
              required: true,
            ),
            field_contract(
              key: "field",
              value_type: :string,
              description: "Field to sort by (for arrays of objects)",
            ),
            field_contract(
              key: "direction",
              value_type: :string,
              description: "Sort direction (asc or desc)",
            ),
          ]
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "sorted", type: :array, description: "Sorted array" },
              { name: "count", type: :number, description: "Number of items" },
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
        field = node_data["field"].to_s.presence
        direction = node_data["direction"].to_s.presence || "asc"

        return NodeResult.new(status: :failure, output: "No collection configured") if collection_expr.blank?

        collection = resolve_collection_reference(context, collection_expr)
        return NodeResult.new(status: :failure, output: "Collection must be an array") unless collection.is_a?(Array)
        if collection.size > MAX_ITEMS
          return NodeResult.new(status: :failure,
                                output: "Collection exceeds maximum of #{MAX_ITEMS}",)
        end

        sorted = sort_collection(collection, field, direction)

        variables = { "sorted" => sorted, "count" => sorted.size }
        NodeResult.new(status: :success, output: "Sorted #{sorted.size} items", variables:)
      end

      private

      def sort_collection(collection, field, direction)
        sorted = if field
                   collection.sort_by { |item| sort_key(item, field) }
                 else
                   collection.sort_by { |item| sort_key_value(item) }
                 end

        direction == "desc" ? sorted.reverse : sorted
      end

      def sort_key(item, field)
        value = case item
                when Hash then item[field] || item[field.to_sym]
                else item
                end
        sort_key_value(value)
      end

      def sort_key_value(value)
        case value
        when Numeric then [0, value]
        when String then [1, value.downcase]
        when NilClass then [2, ""]
        else [1, value.to_s.downcase]
        end
      end
    end
  end
end
