# frozen_string_literal: true

module Missions
  module Nodes
    # Control: Iterator — iterates over an array, executing downstream nodes for each item.
    # Sets `item`, `index`, `total` variables per iteration (port-scoped to "loop").
    class Iterator
      include MissionNodePlugin
      include Missions::CollectionResolver

      DEFAULT_MAX_PARALLEL_BRANCHES = 5
      MAX_ITERATIONS = 1000
      DESIGNER_INSTRUCTIONS = <<~INSTRUCTIONS.strip.freeze
        ## Iterator (type: "iterator")
        Iterates over an array, executing downstream nodes for each item.
        Max #{MAX_ITERATIONS} items.

        ### Configuration
        ```json
        {
          "collection": "items",
          "parallel": false,
          "max_parallel_branches": 5
        }
        ```
        - `collection` (required): Variable name containing the array to iterate.
          Can be a direct variable name (e.g. `items`) or a template (e.g. `{{input.data}}`).
        - `parallel` (optional): When true, iterates in concurrent batches instead of strict sequence.
          Default: `false`.
        - `max_parallel_branches` (optional): Maximum concurrent iteration branches when `parallel`
          is enabled. Default: `#{DEFAULT_MAX_PARALLEL_BRANCHES}`.

        ### How It Works
        1. Resolves the collection variable to an array.
        2. For each item, executes nodes connected to the `loop` port.
        3. Sets `item`, `index`, `total` variables per iteration (scoped to loop port).
        4. After all items, follows the `done` port with collected `results`.
        5. In parallel mode, `results` still preserves the original collection order even if
           individual iterations finish out of order.

        ### Parallel Mode
        - Parallel mode runs loop-body iterations in batches, up to `max_parallel_branches` at a time.
        - Prefer aggregating per-item work through the iterator `results` array on the `done` port.
        - Do not rely on sibling iterations mutating shared variables in a specific order when
          `parallel` is enabled.

        ### Boundary Rules
        - Do not wire a body node back into this iterator node. The iterator reevaluates internally.
        - Do not mix iterator-body inputs with non-body inputs on the same downstream node.
          Route once-per-run continuations through the `done` port when you need post-iteration work.
        - Leaving `done` unconnected is acceptable when the iterator intentionally ends that
          nested body branch and no post-iteration continuation is needed at that level.

        ### Output Ports
        - `loop`: Executed for each item (connect processing nodes here)
        - `done`: Executed after all items are processed

        ### Output Variables
        - `item` (any): Current item [port: loop]
        - `index` (number): Zero-based index [port: loop]
        - `total` (number): Total items [port: loop]
        - `results` (array): Collected results [port: done]

        ### Wiring Pattern
        ```
        Iterator →[loop]→ LLM → (processing) ...
                 →[done]→ Aggregate → Output
        ```
      INSTRUCTIONS

      class << self
        def node_type = "iterator"
        def node_label = "Iterator"
        def node_icon = "fa-solid fa-repeat"
        def node_color = "#0ea5e9"
        def node_category = :control
        def node_description = "Iterates over a collection, executing downstream nodes for each item"

        def field_contracts
          [
            field_contract(
              key: "collection",
              kind: :collection_ref,
              value_type: :array,
              description: "Array to iterate over",
              required: true,
            ),
            field_contract(
              key: "parallel",
              value_type: :boolean,
              description: "Run iteration branches concurrently",
            ),
            field_contract(
              key: "max_parallel_branches",
              value_type: :integer,
              description: "Maximum iteration branches to run concurrently when parallel is enabled",
            ),
          ]
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "item", type: :any, description: "Current item in the iteration", port: "loop" },
              { name: "index", type: :number, description: "Zero-based index of current item", port: "loop" },
              { name: "total", type: :number, description: "Total number of items", port: "loop" },
              { name: "results", type: :array, description: "Collected results after iteration completes",
                port: "done", },
            ],
          )
        end

        def default_output_ports
          [
            { key: "loop", label: "Each Item" },
            { key: "done", label: "Completed" },
          ]
        end

        def designer_instructions = DESIGNER_INSTRUCTIONS
      end

      register_node!

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        collection_expr = node_data["collection"] || node_data["expression"]

        if collection_expr.blank?
          return NodeResult.new(status: :failure, output: "Iterator has no collection configured")
        end

        collection = resolve_collection(context, collection_expr)
        return collection_type_error(collection) unless collection.is_a?(Array)
        return collection_size_error(collection) if collection.size > MAX_ITERATIONS

        store_iterator_metadata(context, collection)
        collection.empty? ? empty_collection_result : first_item_result(context, collection)
      end

      private

      def collection_type_error(collection)
        NodeResult.new(status: :failure, output: "Iterator collection must be an array, got #{collection.class}")
      end

      def collection_size_error(collection)
        NodeResult.new(status: :failure, output: "Collection size #{collection.size} exceeds maximum #{MAX_ITERATIONS}")
      end

      def store_iterator_metadata(context, collection)
        node_data = context.get_variable("_current_node_data") || {}

        context.set_iterator_state(
          context.get_variable("_current_node_id"),
          collection:,
          index: 0,
          total: collection.size,
          results: [],
          parallel: parallel_enabled?(node_data),
          max_parallel_branches: resolved_max_parallel_branches(node_data),
        )
      end

      def parallel_enabled?(node_data)
        !!ActiveModel::Type::Boolean.new.cast(node_data["parallel"])
      end

      def resolved_max_parallel_branches(node_data)
        configured = Integer(node_data["max_parallel_branches"], exception: false)
        max_parallel_branches = configured if configured&.positive?

        (max_parallel_branches || DEFAULT_MAX_PARALLEL_BRANCHES).clamp(1, MAX_ITERATIONS)
      end

      def resolve_collection(context, expression)
        raw_value = context.get_variable(expression)

        if raw_value.is_a?(String)
          parsed = JSON.parse(raw_value)
          return parsed if parsed.is_a?(Array)

          return [raw_value]
        end

        resolve_collection_reference(context, expression, field_name: "iterator collection")
      rescue JSON::ParserError
        resolve_collection_reference(context, expression, field_name: "iterator collection")
      end

      def empty_collection_result
        NodeResult.new(
          status: :success, output: [], next_port: "done",
          variables: { "results" => [], "total" => 0 },
        )
      end

      def first_item_result(_context, collection)
        NodeResult.new(
          status: :success, output: collection.first, next_port: "loop",
          variables: { "item" => collection.first, "index" => 0, "total" => collection.size },
        )
      end
    end
  end
end
