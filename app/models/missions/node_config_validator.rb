# frozen_string_literal: true

module Missions
  # Validates node configuration using ActiveModel validations.
  # Each node type declares field_contracts; this validator checks required and
  # JSON-backed fields from those contracts.
  class NodeConfigValidator
    include ActiveModel::Model

    attr_accessor :node_type, :node_data

    validate :check_required_field_contracts
    validate :check_json_field_contracts
    validate :check_llm_source_configuration
    validate :check_set_variable_expression_conventions
    validate :check_node_specific_config

    # Validates all nodes in a flow_data hash.
    # Returns a Hash of node_id → Array of { field:, message: } error hashes.
    # Only nodes with errors are included.
    def self.validate_flow(flow_data)
      flow_data = Missions::FlowDataSanitizer.sanitize(flow_data)
      errors_by_node = {}
      FlowChecks.apply(flow_data, errors_by_node)

      errors_by_node
    end

    private

    def check_required_field_contracts
      node_class = MissionNodePlugin.resolve(node_type)
      return unless node_class

      node_class.required_field_keys.each do |field|
        value = node_data&.dig(field.to_s)
        errors.add(field.to_sym, "is required") if value.blank?
      end
    end

    def check_json_field_contracts
      node_class = MissionNodePlugin.resolve(node_type)
      return unless node_class

      node_class.json_field_keys.each do |field|
        value = node_data&.dig(field.to_s)
        next if value.blank?

        if field.to_s == "model_routing_config"
          Llm::ModelRoutingConfig.validate!(value, tenant: resolved_tenant)
        else
          Llm::ChatOptions.normalize_custom_params(value)
        end
      rescue Llm::ChatOptions::InvalidCustomParamsError, Llm::ModelRoutingConfig::InvalidConfigError => e
        errors.add(field.to_sym, e.message)
      end
    end

    def check_llm_source_configuration
      return unless node_type.to_s == "llm"

      data = (node_data || {}).to_h.deep_stringify_keys
      source = Missions::LlmNodeRuntimeConfig.source_for(data)
      unless Missions::LlmNodeRuntimeConfig.valid_source?(source)
        errors.add(:llm_config_source, "is not included in the list")
        return
      end
      return unless source == Missions::LlmNodeRuntimeConfig::NODE_SOURCE

      errors.add(:connector_id, "is required when LLM source is Node Configuration") if data["connector_id"].blank?
      errors.add(:model, "is required when LLM source is Node Configuration") if data["model"].blank?
    end

    def check_set_variable_expression_conventions
      return unless node_type.to_s == "set_variable"

      parse_assignments(node_data&.dig("assignments")).each do |name, expression|
        next unless suspicious_string_concatenation?(expression)

        errors.add(
          :assignments,
          "#{name} uses unsupported string concatenation with +; use CONCAT(...) instead",
        )
      end
    end

    def parse_assignments(assignments)
      case assignments
      when Hash
        assignments
      when String
        JSON.parse(assignments)
      else
        {}
      end
    rescue JSON::ParserError
      {}
    end

    def check_node_specific_config
      node_class = MissionNodePlugin.resolve(node_type)
      return unless node_class

      node_class.new.validate_config!(node_data || {})
    rescue ArgumentError => e
      errors.add(:base, e.message)
    end

    def suspicious_string_concatenation?(expression)
      return false unless expression.is_a?(String)
      return false unless expression.include?("+")

      expression.match?(/["']/) || expression.match?(/\bSTR\s*\(/i)
    end

    def resolved_tenant
      Current.tenant || Tenant.default_tenant
    end
  end
end
