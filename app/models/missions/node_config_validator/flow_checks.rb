# frozen_string_literal: true

module Missions
  class NodeConfigValidator
    module FlowChecks
      extend self
      extend FlowCheckHelpers

      NON_SCALAR_FORMULA_TYPES = [:array, :hash].freeze
      BLANK_GLOBAL_MESSAGE = <<~MESSAGE.squish.freeze
        %<key>s is also defined as a blank global variable. Globals are seeded inputs only;
        remove the blank global or give it a real value.
      MESSAGE

      def apply(flow_data, errors_by_node)
        nodes = flow_data&.dig("nodes") || []

        validate_singleton_nodes(nodes, errors_by_node)
        validate_node_configs(nodes, errors_by_node)
        validate_loop_body_boundaries(flow_data, errors_by_node)
        validate_variable_references(flow_data, errors_by_node)
      end

      private

      def validate_singleton_nodes(nodes, errors_by_node)
        singleton_keys = MissionNodePlugin.all_types.select { |type| type[:singleton] }.pluck(:key)
        singleton_keys.each { |type| check_singleton_duplicates(type, nodes, errors_by_node) }
      end

      def check_singleton_duplicates(type, nodes, errors_by_node)
        duplicates = nodes.select { |node| node["type"] == type }
        return if duplicates.size <= 1

        duplicates[1..].each do |node|
          append_error(errors_by_node, node["id"], "type", "Only one #{type} node is allowed per mission")
        end
      end

      def validate_node_configs(nodes, errors_by_node)
        nodes.each do |node|
          validator = NodeConfigValidator.new(node_type: node["type"], node_data: node["data"] || {})
          next if validator.valid?

          errors_by_node[node["id"]] ||= []
          errors_by_node[node["id"]].concat(
            validator.errors.map { |error| { field: error.attribute.to_s, message: error.message } },
          )
        end
      end

      def validate_loop_body_boundaries(flow_data, errors_by_node)
        Missions::LoopBodyBoundaryValidator.errors_for(flow_data).each do |error|
          append_error(errors_by_node, error.node_id, error.field, error.message)
        end
      end

      def validate_variable_references(flow_data, errors_by_node)
        return if flow_data.blank?

        registry = VariableRegistry.new(flow_data)
        nodes = flow_data["nodes"] || []

        validate_blank_global_assignment_conflicts(flow_data, nodes, errors_by_node)

        nodes.each do |node|
          validate_node_variable_references(node, registry, errors_by_node)
          validate_formula_interpolation_usage(node, errors_by_node)
          validate_formula_operand_types(node, registry, errors_by_node)
        end
      end

      def validate_blank_global_assignment_conflicts(flow_data, nodes, errors_by_node)
        blank_global_keys = blank_global_variable_keys(flow_data)
        return if blank_global_keys.empty?

        nodes.each do |node|
          conflicts = assignment_output_keys(node) & blank_global_keys
          next if conflicts.empty?

          conflicts.each do |key|
            append_error(
              errors_by_node,
              node["id"],
              "assignments",
              format(BLANK_GLOBAL_MESSAGE, key:),
            )
          end
        end
      end

      def validate_node_variable_references(node, registry, errors_by_node)
        node_id = node["id"]
        data = node["data"] || {}
        node_class = MissionNodePlugin.resolve(node["type"])
        refs = extract_all_template_refs(data, node_class)
        available_names = available_reference_names(registry, node_id)

        refs.each do |ref|
          next if available_names[:qualified].include?(ref) || available_names[:short].include?(ref)

          append_error(errors_by_node, node_id, "variables", "references unknown variable {{#{ref}}}")
        end

        CollectionReferenceValidator.apply(
          node_id:,
          data:,
          node_class:,
          available_names:,
          errors_by_node:,
        )
      end

      def validate_formula_operand_types(node, registry, errors_by_node)
        available_entries = registry.available_at(node["id"])

        formula_field_pairs(node).each do |field, expression|
          direct_formula_refs(expression).each do |ref|
            entry = available_entries.find { |available| available.qualified_name == ref }
            next unless entry && NON_SCALAR_FORMULA_TYPES.include?(entry.type)

            append_error(
              errors_by_node,
              node["id"],
              field,
              "#{ref} is an array/hash output and cannot be used directly in a formula. Derive a scalar value first.",
            )
          end
        end
      end

      def validate_formula_interpolation_usage(node, errors_by_node)
        interpolation_message =
          "formula fields must use direct variable references, not {{...}} interpolation. " \
          "Use exact variable names such as node.var."

        formula_field_pairs(node).each do |field, expression|
          next unless expression.include?("{{")

          append_error(
            errors_by_node,
            node["id"],
            field,
            interpolation_message,
          )
        end
      end

      def available_reference_names(registry, node_id)
        available_entries = registry.available_at(node_id)
        {
          qualified: available_entries.filter_map(&:qualified_name).to_set,
          short: available_entries.filter_map(&:name).to_set,
        }
      end

      def extract_all_template_refs(data, node_class)
        refs = Set.new
        if node_class&.explicit_reference_field_contracts?
          refs.merge(node_class.reference_names_from_field_contracts(data))
        else
          scan_values_for_refs(data, refs)
        end
        refs
      end

      def blank_global_variable_keys(flow_data)
        (flow_data["global_variables"] || []).filter_map do |variable|
          next if variable["value"].present?

          normalize_variable_key(variable["key"])
        end.to_set
      end

      def assignment_output_keys(node)
        return Set.new unless node["type"] == "set_variable"

        parse_hash_config(node.dig("data", "assignments")).each_key.to_set do |key|
          normalize_variable_key(key)
        end
      end

      def formula_field_pairs(node)
        data = node["data"] || {}
        node_class = MissionNodePlugin.resolve(node["type"])
        fields = contract_formula_field_pairs(node_class, data)

        return fields unless node["type"] == "set_variable"

        fields + assignment_formula_pairs(data)
      end

      def contract_formula_field_pairs(node_class, data)
        return [] unless node_class

        node_class.formula_field_pairs_from_contracts(data)
      end

      def assignment_formula_pairs(data)
        parse_hash_config(data["assignments"]).filter_map do |name, expression|
          next unless formula_like_assignment?(expression)

          ["assignments.#{normalize_variable_key(name)}", expression.to_s]
        end
      end

      def formula_like_assignment?(expression)
        return false unless expression.is_a?(String)
        return false if expression.blank?

        expression.match?(%r{==|!=|<=|>=|<|>|[+\-*/]}) ||
          expression.match?(/\b(and|or|not)\b/i) ||
          expression.match?(/\b[a-z_][a-z0-9_]*\s*\(/i)
      end

      def direct_formula_refs(expression)
        expression
          .gsub(/\{\{[^}]+\}\}/, " ")
          .gsub(/'[^']*'/, " ")
          .gsub(/"[^"]*"/, " ")
          .scan(/\b([a-z_]\w*(?:\.[a-z_]\w*)+)\b/i)
          .flatten
          .to_set
      end
    end
  end
end
