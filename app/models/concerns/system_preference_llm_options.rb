# frozen_string_literal: true

module SystemPreferenceLlmOptions
  extend ActiveSupport::Concern

  DEFAULT_TEMPERATURE = 0.7
  TEMPERATURE_RANGE = (0.0..2.0)
  THINKING_EFFORTS = Llm::ChatOptions::THINKING_EFFORTS

  included do
    validate :temperature_must_be_in_range
    validate :thinking_effort_must_be_valid
    validate :thinking_budget_must_be_positive
    validate :custom_llm_params_must_be_valid
    validate :model_routing_config_must_be_valid
  end

  def temperature
    (self[:temperature] || DEFAULT_TEMPERATURE).to_f
  end

  def custom_llm_params
    raw = self[:custom_llm_params]
    raw.is_a?(Hash) ? raw : {}
  end

  def custom_llm_params=(value)
    @custom_llm_params_error = nil

    normalized = Llm::ChatOptions.normalize_custom_params(value)
    @custom_llm_params_json_input = normalized.present? ? JSON.pretty_generate(normalized) : ""
    super(normalized)
  rescue Llm::ChatOptions::InvalidCustomParamsError => e
    @custom_llm_params_json_input = custom_llm_params_json_input(value)
    @custom_llm_params_error = e.message
  end

  def custom_llm_params_json
    return @custom_llm_params_json_input if defined?(@custom_llm_params_json_input)

    params = custom_llm_params
    params.present? ? JSON.pretty_generate(params) : ""
  end

  def model_routing_config
    raw = self[:model_routing_config]
    return Llm::ModelRoutingConfig.default if raw.blank?

    Llm::ModelRoutingConfig.normalize(raw)
  rescue Llm::ModelRoutingConfig::InvalidConfigError
    Llm::ModelRoutingConfig.default
  end

  def model_routing_config=(value)
    @model_routing_config_error = nil

    normalized = Llm::ModelRoutingConfig.validate!(value, tenant:)
    @model_routing_config_json_input = formatted_model_routing_config_input(normalized)
    self[:model_routing_config] = Llm::ModelRoutingConfig.persistable(normalized)
  rescue Llm::ModelRoutingConfig::InvalidConfigError => e
    @model_routing_config_json_input = model_routing_config_json_input(value)
    @model_routing_config_error = e.message
  end

  def model_routing_config_json
    return @model_routing_config_json_input if defined?(@model_routing_config_json_input)

    config = model_routing_config
    config == Llm::ModelRoutingConfig.default ? "" : JSON.pretty_generate(config)
  end

  def llm_runtime_settings
    {
      connector_id: llm_connector_id,
      context: resolve_llm_context,
      model_id:,
      temperature:,
      thinking_effort: thinking_effort.presence,
      thinking_budget: thinking_budget.presence,
      custom_params: custom_llm_params,
      model_routing_config:,
    }
  end

  private

  def temperature_must_be_in_range
    return if self[:temperature].blank?
    return if TEMPERATURE_RANGE.cover?(temperature)

    errors.add(:temperature, "must be between 0.0 and 2.0")
  end

  def thinking_effort_must_be_valid
    return if thinking_effort.blank? || thinking_effort.in?(THINKING_EFFORTS)

    errors.add(:thinking_effort, "is not included in the list")
  end

  def thinking_budget_must_be_positive
    return if thinking_budget.blank?

    errors.add(:thinking_budget, "must be greater than 0") if thinking_budget <= 0
  end

  def custom_llm_params_must_be_valid
    return if @custom_llm_params_error.blank?

    errors.add(:custom_llm_params, @custom_llm_params_error)
  end

  def model_routing_config_must_be_valid
    return if @model_routing_config_error.blank?

    errors.add(:model_routing_config, @model_routing_config_error)
  end

  def custom_llm_params_json_input(value)
    return value if value.is_a?(String)
    return "" if value.blank?

    JSON.pretty_generate(value)
  rescue JSON::JSONError
    value.to_s
  end

  def model_routing_config_json_input(value)
    return value if value.is_a?(String)
    return "" if value.blank?

    JSON.pretty_generate(value)
  rescue JSON::JSONError
    value.to_s
  end

  def formatted_model_routing_config_input(normalized)
    normalized == Llm::ModelRoutingConfig.default ? "" : JSON.pretty_generate(normalized)
  end
end
