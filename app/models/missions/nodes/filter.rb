# frozen_string_literal: true

module Missions
  module Nodes
    # Control: Filter — filters an array based on an expression evaluated per item.
    # Outputs matching items on "match" port, rejects on "no_match" port.
    class Filter
      include MissionNodePlugin
      include Missions::CollectionResolver

      MAX_ITEMS = 10_000
      RUNTIME_BRANCH_PRUNING_GUIDANCE = <<~GUIDANCE.strip.freeze
        ### Runtime Branch Pruning
        - When the filter completes, only one of `match` or `no_match` stays enabled.
        - The non-selected port is disabled at runtime, and nodes fed only by disabled paths are disabled too.
        - Downstream joins wait only on the surviving predecessors.
      GUIDANCE

      class << self
        def node_type = "filter"
        def node_label = "Filter"
        def node_icon = "fa-solid fa-filter"
        def node_color = "#0d9488"
        def node_category = :control
        def node_description = "Filters array items based on an expression"

        def field_contracts
          [
            field_contract(
              key: "collection",
              kind: :collection_ref,
              value_type: :array,
              description: "Array to filter",
              required: true,
            ),
            field_contract(
              key: "expression",
              kind: :formula,
              value_type: :string,
              description: "Filter expression evaluated per item",
              required: true,
            ),
          ]
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "matches", type: :array, description: "Items matching the filter", port: "match" },
              { name: "rejects", type: :array, description: "Items not matching the filter", port: "no_match" },
              { name: "match_count", type: :number, description: "Number of matching items" },
              { name: "total_count", type: :number, description: "Total number of items" },
            ],
          )
        end

        def default_output_ports
          [
            { key: "match", label: "Matches" },
            { key: "no_match", label: "No Match" },
          ]
        end

        def mutually_exclusive_output_ports? = true

        def designer_instructions
          <<~INSTRUCTIONS.strip
            ## Filter (type: "filter")
            Filters array items based on a per-item expression. Max #{MAX_ITEMS} items.

            ### Configuration
            ```json
            {
              "collection": "items",
              "expression": "item > 10"
            }
            ```
            - `collection` (required): Variable name containing the array to filter
            - `expression` (required): Expression evaluated for each item.
              The current item is available as the `item` variable.
              For objects: access fields with dot notation in the expression.

            ### Output Ports
            - `match`: Followed when at least one item matches
            - `no_match`: Followed when no items match

            #{RUNTIME_BRANCH_PRUNING_GUIDANCE}

            ### Output Variables
            - `matches` (array): Items that matched [port: match]
            - `rejects` (array): Items that didn't match [port: no_match]
            - `match_count` (number): Count of matches
            - `total_count` (number): Total items processed
          INSTRUCTIONS
        end
      end

      register_node!

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        collection_expr = node_data["collection"].to_s
        expression = node_data["expression"].to_s

        return missing_filter_configuration(collection_expr) if collection_expr.blank? || expression.blank?

        collection = resolve_collection_reference(context, collection_expr)
        collection_error = validate_filter_collection(collection)
        return collection_error if collection_error

        matches, rejects = partition_collection(context, collection, expression)
        filter_result(matches:, rejects:, total_count: collection.size)
      end

      private

      def missing_filter_configuration(collection_expr)
        message = collection_expr.blank? ? "No collection configured" : "No filter expression configured"
        NodeResult.new(status: :failure, output: message)
      end

      def validate_filter_collection(collection)
        return NodeResult.new(status: :failure, output: "Collection must be an array") unless collection.is_a?(Array)
        return if collection.size <= MAX_ITEMS

        NodeResult.new(status: :failure, output: "Collection exceeds maximum of #{MAX_ITEMS}")
      end

      def filter_result(matches:, rejects:, total_count:)
        variables = {
          "matches" => matches,
          "rejects" => rejects,
          "match_count" => matches.size,
          "total_count" => total_count,
        }

        port = matches.any? ? "match" : "no_match"
        NodeResult.new(status: :success, output: "#{matches.size}/#{total_count} items matched", next_port: port,
                       variables:,)
      end

      def partition_collection(context, collection, expression)
        matches = []
        rejects = []
        had_runtime_item = context.runtime_variable_set?("item")
        previous_item = context.get_variable("item")

        collection.each do |item|
          context.set_runtime_variable("item", item)
          result = context.evaluate(expression)
          if result
            matches << item
          else
            rejects << item
          end
        end

        if had_runtime_item
          context.set_runtime_variable("item", previous_item)
        else
          context.clear_runtime_variable("item")
        end
        [matches, rejects]
      end
    end
  end
end
