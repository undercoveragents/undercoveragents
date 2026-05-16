# frozen_string_literal: true

module Missions
  # Shared resolver for mission node configuration values.
  #
  # Nodes should not each decide independently whether a field is a template,
  # a formula, a variable reference, or a collection literal. This resolver
  # centralizes those rules so runtime behavior stays consistent.
  class ValueResolver
    attr_reader :context

    def initialize(context)
      @context = context
    end

    def formula_or_literal(expression)
      rendered = template(expression)
      evaluated = context.evaluate(rendered)
      evaluated.nil? ? rendered : evaluated
    end

    def formula(expression)
      context.evaluate(template(expression))
    end

    def formula!(expression)
      context.evaluate!(template(expression))
    end

    def template(value)
      context.interpolate(value.to_s)
    end

    def integer(value, label:, default: nil, minimum: 0)
      return default if value.blank? && !default.nil?
      return nil if value.blank?

      integer = Integer(formula_or_literal(value))
      raise ExecutionError, "#{label.capitalize} must be at least #{minimum}" if integer < minimum

      integer
    rescue ArgumentError, TypeError
      raise ExecutionError, "Invalid #{label}: #{value}"
    end

    def collection(expression, field_name: "collection")
      raw_expression = expression.to_s

      if raw_expression.include?("{{")
        rendered = template(raw_expression)
        return collection_literal(rendered, field_name:) unless rendered.include?("{{")

        raise_undefined_collection(raw_expression, field_name)
      end

      value = context.get_variable(raw_expression)
      return collection_value(value) unless value.nil?

      collection_literal(raw_expression, field_name:)
    end

    private

    def collection_value(value)
      case value
      when Array then value
      when String then parse_collection_variable(value)
      else [value]
      end
    end

    def collection_literal(expression, field_name:)
      parsed = JSON.parse(expression)
      return parsed if parsed.is_a?(Array)

      raise_undefined_collection(expression, field_name)
    rescue JSON::ParserError
      return expression.split(",").map(&:strip) if expression.include?(",")

      raise_undefined_collection(expression, field_name)
    end

    def parse_collection_variable(value)
      JSON.parse(value)
    rescue JSON::ParserError
      return value.split(",").map(&:strip) if value.include?(",")

      [value]
    end

    def raise_undefined_collection(expression, field_name)
      raise Missions::ExecutionError,
            "#{field_name.capitalize} variable '#{expression}' is not defined - set it before this node"
    end
  end
end
