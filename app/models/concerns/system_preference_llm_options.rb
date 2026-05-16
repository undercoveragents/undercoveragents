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

  def llm_runtime_settings
    {
      connector_id: llm_connector_id,
      context: resolve_llm_context,
      model_id:,
      temperature:,
      thinking_effort: thinking_effort.presence,
      thinking_budget: thinking_budget.presence,
      custom_params: custom_llm_params,
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

  def custom_llm_params_json_input(value)
    return value if value.is_a?(String)
    return "" if value.blank?

    JSON.pretty_generate(value)
  rescue JSON::JSONError
    value.to_s
  end
end
