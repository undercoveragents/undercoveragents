# frozen_string_literal: true

module Missions
  module Nodes
    # Control: Unique — removes duplicate values from an array.
    # Can deduplicate by a specific field for arrays of objects.
    class Unique
      include MissionNodePlugin
      include Missions::CollectionResolver

      class << self
        def node_type = "unique"
        def node_label = "Remove Duplicates"
        def node_icon = "fa-solid fa-clone"
        def node_color = "#0891b2"
        def node_category = :control
        def node_description = "Removes duplicate items from an array"

        def field_contracts
          [
            field_contract(
              key: "collection",
              kind: :collection_ref,
              value_type: :array,
              description: "Array to deduplicate",
              required: true,
            ),
            field_contract(
              key: "field",
              value_type: :string,
              description: "Field to compare (for arrays of objects)",
            ),
          ]
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "unique", type: :array, description: "Deduplicated array" },
              { name: "duplicates", type: :array, description: "Removed duplicate items" },
              { name: "count", type: :number, description: "Number of unique items" },
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

        return NodeResult.new(status: :failure, output: "No collection configured") if collection_expr.blank?

        collection = resolve_and_validate_collection(context, collection_expr)
        return collection if collection.is_a?(NodeResult)

        unique_items, duplicate_items = deduplicate(collection, field)

        variables = {
          "unique" => unique_items,
          "duplicates" => duplicate_items,
          "count" => unique_items.size,
        }
        NodeResult.new(
          status: :success,
          output: "#{unique_items.size} unique items (#{duplicate_items.size} duplicates removed)",
          variables:,
        )
      end

      private

      def resolve_and_validate_collection(context, expr)
        collection = resolve_collection_reference(context, expr)
        return NodeResult.new(status: :failure, output: "Collection must be an array") unless collection.is_a?(Array)
        if collection.size > MAX_ITEMS
          return NodeResult.new(status: :failure,
                                output: "Collection exceeds maximum of #{MAX_ITEMS}",)
        end

        collection
      end

      def deduplicate(collection, field)
        seen = Set.new
        unique = []
        duplicates = []

        collection.each do |item|
          key = field ? extract_field(item, field) : item
          if seen.include?(key)
            duplicates << item
          else
            seen.add(key)
            unique << item
          end
        end

        [unique, duplicates]
      end

      def extract_field(item, field)
        case item
        when Hash then item[field] || item[field.to_sym]
        else item
        end
      end
    end
  end
end
