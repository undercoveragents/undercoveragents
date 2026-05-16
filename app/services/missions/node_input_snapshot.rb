# frozen_string_literal: true

module Missions
  class NodeInputSnapshot
    IGNORED_FALLBACK_KEYS = ["label", "name", "description", "output_ports"].freeze

    def initialize(node_type:, node_data:, context:)
      @node_type = node_type.to_s
      @node_data = node_data.is_a?(Hash) ? node_data : {}
      @context = context
      @node_class = MissionNodePlugin.resolve(@node_type)
      @resolver = Missions::ValueResolver.new(context)
    end

    def call
      contracts = Array(@node_class&.field_contracts)
      snapshot = contracts.any? ? snapshot_from_contracts(contracts) : fallback_snapshot
      snapshot.is_a?(Hash) ? snapshot.compact : snapshot
    rescue StandardError
      fallback_snapshot
    end

    private

    def snapshot_from_contracts(contracts)
      contracts.each_with_object({}) do |contract, snapshot|
        next unless @node_data.key?(contract.key)

        snapshot[contract.key] = resolve_contract_value(contract, @node_data[contract.key])
      end
    end

    def resolve_contract_value(contract, raw_value)
      case contract.kind
      when :template
        resolve_template_value(raw_value, contract.value_type)
      when :formula
        resolve_formula_value(raw_value)
      when :collection_ref
        resolve_collection_value(raw_value, contract.key)
      when :assignment_map
        resolve_assignment_map(raw_value)
      when :input_fields
        resolve_input_fields(raw_value)
      else
        normalize_value(raw_value, contract.value_type)
      end
    end

    def resolve_template_value(raw_value, value_type)
      interpolate_value(normalize_value(raw_value, value_type))
    end

    def resolve_formula_value(raw_value)
      return raw_value unless raw_value.is_a?(String)

      @resolver.formula_or_literal(raw_value)
    rescue StandardError
      @context.interpolate(raw_value)
    end

    def resolve_collection_value(raw_value, field_name)
      return raw_value if raw_value.nil?

      @resolver.collection(raw_value.to_s, field_name:)
    rescue StandardError
      @context.interpolate(raw_value.to_s)
    end

    def resolve_assignment_map(raw_value)
      normalize_hash(raw_value).each_with_object({}) do |(key, value), resolved|
        resolved[key.to_s] = resolve_formula_value(value)
      end
    end

    def resolve_input_fields(raw_value)
      fields = normalize_array(raw_value)
      return { "input" => @context.get_variable("input") } if fields.empty?

      trigger_data = @context.get_variable("_trigger_data") || {}

      fields.each_with_object({}) do |field, values|
        append_input_field_value(values, field, trigger_data) if field.is_a?(Hash)
      end
    end

    def append_input_field_value(values, field, trigger_data)
      name = input_field_name(field)
      return if name.blank?

      value = input_field_value(field, trigger_data, name)
      values[name.to_s] = coerce_input_field_value(value, input_field_type(field))
    end

    def input_field_name(field)
      field["variable_name"] || field[:variable_name]
    end

    def input_field_type(field)
      field["field_type"] || field[:field_type]
    end

    def input_field_value(field, trigger_data, name)
      value = trigger_data[name]
      default_value = field.dig("config", "default_value") || field.dig(:config, :default_value)

      value.nil? && default_value.present? ? default_value : value
    end

    def coerce_input_field_value(value, field_type)
      return value if value.nil?

      coercer = Missions::Nodes::Input::COERCERS[field_type.to_s]
      coercer ? coercer.call(value) : value
    rescue JSON::ParserError
      value
    end

    def normalize_value(raw_value, value_type)
      case value_type
      when :hash
        normalize_hash(raw_value)
      when :array
        normalize_array(raw_value)
      when :boolean
        ActiveModel::Type::Boolean.new.cast(raw_value)
      when :integer
        integer_or_original(raw_value)
      when :number
        numeric_or_original(raw_value)
      else
        duplicate_value(raw_value)
      end
    end

    def normalize_hash(raw_value)
      case raw_value
      when Hash
        duplicate_value(raw_value)
      when String
        parsed = JSON.parse(raw_value)
        parsed.is_a?(Hash) ? parsed : { "value" => parsed }
      else
        {}
      end
    rescue JSON::ParserError
      {}
    end

    def normalize_array(raw_value)
      case raw_value
      when Array
        duplicate_value(raw_value)
      when String
        parsed = JSON.parse(raw_value)
        parsed.is_a?(Array) ? parsed : [parsed]
      when nil
        []
      else
        [duplicate_value(raw_value)]
      end
    rescue JSON::ParserError
      []
    end

    def integer_or_original(value)
      return value if value.is_a?(Integer)

      Integer(value, exception: false) || value
    end

    def numeric_or_original(value)
      return value if value.is_a?(Numeric)

      integer = Integer(value, exception: false)
      return integer unless integer.nil?

      Float(value, exception: false) || value
    end

    def interpolate_value(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), resolved|
          resolved[key.to_s] = interpolate_value(nested_value)
        end
      when Array
        value.map { |nested_value| interpolate_value(nested_value) }
      when String
        @context.interpolate(value)
      else
        value
      end
    end

    def fallback_snapshot
      @node_data.except(*IGNORED_FALLBACK_KEYS).each_with_object({}) do |(key, value), snapshot|
        snapshot[key.to_s] = duplicate_value(value)
      end
    end

    def duplicate_value(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), duplicate|
          duplicate[key.to_s] = duplicate_value(nested_value)
        end
      when Array
        value.map { |nested_value| duplicate_value(nested_value) }
      else
        value
      end
    end
  end
end
