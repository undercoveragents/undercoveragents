# frozen_string_literal: true

module Missions
  module ExecutionContextValueStore
    def initialize_value_store
      @calculator = build_calculator
      @variables = {}
      @node_variables = {}
    end

    def set_variable(name, value)
      key = normalize_key(name)

      if transient_node_variable?(key)
        transient_state_for_current_task[key] = value
      else
        persist_variable(key, value)
      end

      value
    end

    def get_variable(name)
      key = normalize_key(name)

      if runtime_helper_variable?(key)
        transient_state = transient_state_for_current_task
        return transient_state[key] if transient_state.key?(key)
      end

      return resolve_node_variable(name) if name.to_s.include?(".")

      @variables[key]
    end

    def variables
      @variables.dup
    end

    def set_node_variables(node_name, variables_hash)
      node_key = normalize_key(node_name)
      @node_variables[node_key] ||= {}

      variables_hash.each do |var_name, value|
        variable_key = normalize_key(var_name)
        @node_variables[node_key][variable_key] = value
      end
    end

    def merge_variables(hash)
      hash.each { |key, value| set_variable(key, value) }
    end

    def evaluate(expression)
      expr = dentaku_translate(expression)
      calculator.evaluate(expr, dentaku_vars(runtime_expression_variables))
    rescue Dentaku::Error, ZeroDivisionError
      nil
    end

    def evaluate!(expression)
      expr = dentaku_translate(expression)
      calculator.evaluate!(expr, dentaku_vars(runtime_expression_variables))
    rescue Dentaku::Error, ZeroDivisionError => e
      raise Missions::ExpressionError, "Failed to evaluate '#{expression}': #{e.message}"
    end

    def interpolate(template)
      return template unless template.is_a?(String)

      template.gsub(/\{\{([\w.]+)\}\}/) do
        ref = Regexp.last_match(1)
        value = get_variable(ref)
        value.nil? ? "{{#{ref}}}" : stringify_value(value)
      end
    end

    def restore_from(state)
      restore_global_variables(state)
      restore_node_variables(state)
    end

    private

    def persist_variable(key, value)
      @variables[key] = value
      calculator.store(key => value) if dentaku_compatible?(value)
    end

    def normalize_key(name)
      name.to_s.downcase.gsub(/[^a-z0-9_]/, "_")
    end

    def resolve_node_variable(name)
      node_name, variable_name = name.to_s.split(".", 2)
      node_key = normalize_key(node_name)
      variable_key = normalize_key(variable_name)

      @node_variables.dig(node_key, variable_key)
    end

    def stringify_value(value)
      return value.to_json if value.is_a?(Hash) || value.is_a?(Array)

      value.to_s
    end

    def serialized_node_variables
      @node_variables.transform_values do |value|
        value.transform_keys(&:to_s)
      end
    end

    def build_calculator
      Dentaku::Calculator.new.tap do |instance|
        instance.add_function(:str, :string, ->(arg) { arg.to_s })
        instance.add_function(:dig, :string, ->(*args) { self.class.json_dig(*args) })
        instance.add_function(
          :length,
          :numeric,
          ->(arg) { arg.respond_to?(:length) ? arg.length : arg.to_s.length },
        )
      end
    end

    def dentaku_translate(expression)
      return expression unless expression.is_a?(String)

      expression.gsub(/\b[a-z_]\w*(?:\.[a-z_]\w*)+\b/i) { |match| match.split(".").join("__") }
    end

    def dentaku_vars(extra_vars = {})
      runtime_vars = flattened_runtime_expression_variables(extra_vars)

      @variables
        .select { |_, value| dentaku_compatible?(value) }
        .merge(flattened_node_variables)
        .merge(runtime_vars)
    end

    def flattened_node_variables
      @node_variables.each_with_object({}) do |(node_key, values), flattened|
        values.each do |variable_key, value|
          next unless dentaku_compatible?(value)

          flattened["#{node_key}__#{variable_key}"] = value
        end
      end
    end

    def flattened_runtime_expression_variables(extra_vars)
      extra_vars.each_with_object({}) do |(key, value), flattened|
        flatten_runtime_expression_value(flattened, normalize_key(key), value)
      end
    end

    def flatten_runtime_expression_value(flattened, key, value)
      flattened[key] = value if dentaku_compatible?(value)
      return unless value.is_a?(Hash)

      value.each do |child_key, child_value|
        flatten_runtime_expression_value(flattened, "#{key}__#{normalize_key(child_key)}", child_value)
      end
    end

    def dentaku_compatible?(value)
      value.is_a?(Numeric) || value.is_a?(String) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
    end

    def restore_global_variables(state)
      (state["variables"] || {}).each { |key, value| set_variable(key, value) }
    end

    def restore_node_variables(state)
      (state["node_variables"] || {}).each { |node_name, values| set_node_variables(node_name, values) }
    end
  end
end
