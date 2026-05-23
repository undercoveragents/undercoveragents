# frozen_string_literal: true

module AgentConfigurationValidations
  extend ActiveSupport::Concern

  INPUT_FIELD_TYPES = [
    "string", "string_array",
    "number", "number_array",
    "boolean", "boolean_array",
    "file", "file_array",
    "json",
    "date", "date_array",
    "datetime", "datetime_array",
  ].freeze

  included do
    before_validation :ensure_configuration
    before_validation :normalize_response_format_configuration
    validate :validate_configuration_fields
    validate :llm_connector_must_be_llm_provider
  end

  private

  def ensure_configuration
    self.configuration = {} unless configuration.is_a?(Hash)
  end

  def validate_configuration_fields
    validate_description_length
    validate_agent_type_length
    validate_llm_config_source
    validate_model_id_presence_and_length
    validate_temperature_presence_and_range
    validate_thinking_effort
    validate_thinking_budget
    validate_custom_llm_params
    validate_model_routing_config
    validate_response_format
    validate_response_schema
    validate_input_schema
    validate_builtin_metadata
  end

  def validate_description_length
    return unless description.present? && description.length > 500

    errors.add(:description, "is too long (maximum is 500 characters)")
  end

  def validate_agent_type_length
    return unless agent_type.present? && agent_type.length > 100

    errors.add(:agent_type, "is too long (maximum is 100 characters)")
  end

  def validate_llm_config_source
    return if llm_config_source.in?(AgentConfiguration::LLM_CONFIG_SOURCES)

    errors.add(:llm_config_source, "is not included in the list")
  end

  def validate_model_id_presence_and_length
    errors.add(:model_id, "can't be blank") if llm_config_source == "agent" && model_id.blank?
    errors.add(:model_id, "is too long (maximum is 200 characters)") if model_id.present? && model_id.length > 200
  end

  def validate_temperature_presence_and_range
    errors.add(:temperature, "can't be blank") if configuration["temperature"].nil?
    return if configuration["temperature"].nil?

    errors.add(:temperature, "must be greater than or equal to 0.0") if temperature < 0.0
    errors.add(:temperature, "must be less than or equal to 2.0") if temperature > 2.0
  end

  def validate_thinking_effort
    return if thinking_effort.blank? || thinking_effort.in?(AgentConfiguration::THINKING_EFFORTS)

    errors.add(:thinking_effort, "is not included in the list")
  end

  def validate_thinking_budget
    return if thinking_budget.blank?

    errors.add(:thinking_budget, "must be greater than 0") if thinking_budget <= 0
  end

  def validate_custom_llm_params
    return if @custom_llm_params_error.blank?

    errors.add(:custom_llm_params, @custom_llm_params_error)
  end

  def validate_model_routing_config
    return if @model_routing_config_error.blank?

    errors.add(:model_routing_config, @model_routing_config_error)
  end

  def validate_response_format
    return if response_format.in?(AgentConfiguration::RESPONSE_FORMATS)

    errors.add(:response_format, "is not included in the list")
  end

  def validate_response_schema
    return unless response_format == "json_schema"
    return errors.add(:response_schema, @response_schema_error) if @response_schema_error.present?

    schema = response_schema
    errors.add(:response_schema, "can't be blank") if schema.blank?
    errors.add(:response_schema, "must include a type") if schema.present? && schema["type"].blank?
  end

  def llm_connector_must_be_llm_provider
    return if llm_connector_id.blank?
    return if llm_connector&.connector_type == "llm_provider"

    errors.add(:llm_connector_id, "must be an LLM Provider connector")
  end

  def validate_input_schema
    input_schema.each_with_index do |field, index|
      validate_input_schema_field(field, index)
    end
  end

  def validate_input_schema_field(field, index)
    field_name = field["variable_name"].to_s
    errors.add(:input_schema, "field ##{index + 1} must include a variable_name") if field_name.blank?
    errors.add(:input_schema, "field ##{index + 1} must include a label") if field["label"].to_s.blank?
    return if field["field_type"].to_s.in?(INPUT_FIELD_TYPES)

    errors.add(:input_schema, "field ##{index + 1} has an invalid field_type")
  end

  def validate_builtin_metadata
    return unless builtin?
    return if builtin_key.present?

    errors.add(:builtin_key, "can't be blank for builtin agents")
  end

  def normalize_response_format_configuration
    configuration.delete("response_schema") unless configuration["response_format"] == "json_schema"
  end
end
