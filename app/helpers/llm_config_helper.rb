# frozen_string_literal: true

module LlmConfigHelper
  THINKING_EFFORT_OPTIONS = [
    ["Model default", ""],
    ["Off", "none"],
    ["Low", "low"],
    ["Medium", "medium"],
    ["High", "high"],
  ].freeze

  def thinking_effort_options_for_select
    THINKING_EFFORT_OPTIONS
  end

  def llm_model_option_properties(model_record)
    {
      provider: model_record.provider,
      supports_temperature: model_record.supports_temperature?,
      supports_reasoning: model_record.supports_reasoning?,
    }
  end
end
