# frozen_string_literal: true

module AgentLlmConfiguration
  extend ActiveSupport::Concern

  def model_id
    configuration["model_id"]
  end

  def model_id=(value)
    self.configuration = (configuration || {}).merge("model_id" => value)
  end

  def temperature
    (configuration["temperature"] || AgentConfiguration::DEFAULT_TEMPERATURE).to_f
  end

  def temperature=(value)
    self.configuration = (configuration || {}).merge("temperature" => value&.to_f)
  end

  def thinking_effort
    configuration["thinking_effort"].presence
  end

  def thinking_effort=(value)
    self.configuration = (configuration || {}).merge("thinking_effort" => value.to_s.presence)
  end

  def thinking_budget
    configuration["thinking_budget"]&.to_i.presence
  end

  def thinking_budget=(value)
    self.configuration = (configuration || {}).merge("thinking_budget" => value.presence&.to_i)
  end

  def custom_llm_params
    raw = configuration["custom_llm_params"]
    raw.is_a?(Hash) ? raw : {}
  end

  def custom_llm_params=(value)
    @custom_llm_params_error = nil

    normalized = Llm::ChatOptions.normalize_custom_params(value)
    @custom_llm_params_json_input = normalized.present? ? JSON.pretty_generate(normalized) : ""
    merged = (configuration || {}).merge("custom_llm_params" => normalized)
    merged.delete("custom_llm_params") if normalized.blank?
    self.configuration = merged
  rescue Llm::ChatOptions::InvalidCustomParamsError => e
    @custom_llm_params_json_input = custom_llm_params_json_input(value)
    @custom_llm_params_error = e.message
  end

  def custom_llm_params_json
    return @custom_llm_params_json_input if defined?(@custom_llm_params_json_input)

    params = custom_llm_params
    params.present? ? JSON.pretty_generate(params) : ""
  end

  def llm_config_source
    configuration["llm_config_source"].presence || AgentConfiguration::DEFAULT_LLM_CONFIG_SOURCE
  end

  def llm_config_source=(value)
    default_source = AgentConfiguration::DEFAULT_LLM_CONFIG_SOURCE
    self.configuration = (configuration || {}).merge("llm_config_source" => value.presence || default_source)
  end

  def input_schema
    normalize_input_schema(configuration["input_schema"])
  end

  def input_schema=(value)
    self.configuration = (configuration || {}).merge("input_schema" => normalize_input_schema(value))
  end

  def runtime_tool_keys
    Array(configuration["tools"] || configuration["runtime_tool_keys"]).map(&:to_s).compact_blank
  end

  def runtime_tool_keys=(value)
    normalized = Array(value).map(&:to_s).compact_blank
    merged_configuration = (configuration || {}).merge("tools" => normalized)
    merged_configuration.delete("runtime_tool_keys")
    self.configuration = merged_configuration
  end

  def llm_connector_id
    configuration["llm_connector_id"]&.to_i.presence
  end

  def llm_connector_id=(value)
    self.configuration = (configuration || {}).merge("llm_connector_id" => value.presence&.to_i)
  end

  def llm_connector
    return nil if llm_connector_id.blank?

    ConnectorLookup.find(llm_connector_id, tenant: respond_to?(:tenant) ? tenant : nil)
  end

  def llm_connector=(connector)
    self.llm_connector_id = connector&.id
  end

  def resolve_llm_context
    return resolve_system_preference_llm_context if llm_config_source == "system_preference"
    return nil if llm_connector_id.blank?

    llm_connector&.build_context
  end

  private

  def resolve_system_preference_llm_context
    preference = SystemPreference.current(tenant:)
    preference.resolve_llm_context if preference.configured?
  end

  def normalize_input_schema(value)
    raw_input_schema_fields(value).filter_map { |field| normalize_input_schema_field(field) }
  rescue JSON::ParserError
    []
  end

  def raw_input_schema_fields(value)
    case value
    when String then JSON.parse(value)
    when Array then value
    when nil then []
    else Array.wrap(value)
    end
  end

  def normalize_input_schema_field(field)
    return unless field.respond_to?(:to_h)

    normalized = field.to_h.deep_stringify_keys
    {
      "variable_name" => normalized["variable_name"].presence || normalized["name"].presence,
      "label" => normalized["label"].presence,
      "field_type" => normalized["field_type"].presence || "string",
      "required" => ActiveModel::Type::Boolean.new.cast(normalized["required"]),
      "config" => normalized.fetch("config", {}).to_h.deep_stringify_keys,
    }
  end

  def custom_llm_params_json_input(value)
    value.is_a?(String) ? value : ""
  end
end
