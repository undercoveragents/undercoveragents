# frozen_string_literal: true

module Llm
  class ChatOptions
    class InvalidCustomParamsError < ArgumentError; end

    THINKING_EFFORTS = ["none", "low", "medium", "high"].freeze

    def self.apply_to_chat(chat:, model_id:, model_record: nil, tools_present: false, **settings)
      resolved_model = model_record || resolve_model(model_id)
      thinking_settings = {
        effort: settings[:thinking_effort],
        budget: settings[:thinking_budget],
      }
      custom_params = effective_custom_params(
        settings[:custom_params],
        resolved_model,
        thinking_effort: settings[:thinking_effort],
        tools_present:,
      )

      apply_temperature(chat, settings[:temperature], resolved_model)
      apply_thinking(chat, resolved_model, thinking_settings, tools_present:, custom_params:)
      apply_custom_params(chat, custom_params)

      resolved_model
    end

    def self.normalize_custom_params(value)
      case value
      when nil
        {}
      when String
        normalize_custom_params_string(value)
      when Hash
        value.deep_stringify_keys
      else
        return {} unless value.respond_to?(:to_h)

        value.to_h.deep_stringify_keys
      end
    end

    def self.thinking_options(effort:, budget:)
      options = {}
      normalized_effort = effort.to_s.presence
      normalized_budget = budget.presence

      return nil if normalized_effort == "none"

      if normalized_effort.present?
        raise ArgumentError, "Thinking effort is invalid" unless normalized_effort.in?(THINKING_EFFORTS)

        options[:effort] = normalized_effort.to_sym
      end

      options[:budget] = Integer(normalized_budget) if normalized_budget.present? && normalized_effort != "none"

      options.presence
    end

    def self.resolve_model(model_id)
      return nil if model_id.blank?

      Model.find_by(model_id:)
    end

    def self.apply_temperature(chat, temperature, model_record)
      return if temperature.nil?
      return if model_record&.supports_temperature? == false

      chat.with_temperature(temperature.to_f)
    end
    private_class_method :apply_temperature

    def self.apply_thinking(chat, model_record, thinking_settings, tools_present: false, custom_params: {})
      options = thinking_options(**thinking_settings)
      return if options.blank?
      return if custom_thinking_type(custom_params) == "disabled"
      return if model_record&.supports_reasoning? == false
      return if skip_tool_reasoning_for_provider?(model_record, tools_present:)

      chat.with_thinking(**options)
    end
    private_class_method :apply_thinking

    def self.skip_tool_reasoning_for_provider?(model_record, tools_present: false)
      tools_present && model_record&.provider.to_s == "deepseek"
    end
    private_class_method :skip_tool_reasoning_for_provider?

    def self.apply_custom_params(chat, custom_params)
      return if custom_params.blank?

      chat.with_params(**custom_params.deep_symbolize_keys)
    end
    private_class_method :apply_custom_params

    def self.effective_custom_params(custom_params, model_record, thinking_effort:, tools_present: false)
      params = normalize_custom_params(custom_params)
      return params unless model_record&.provider.to_s == "deepseek"

      params = flatten_deepseek_extra_body(params)
      return merge_deepseek_thinking_type(params, "disabled") if tools_present
      return params if custom_thinking_type(params).present?
      return merge_deepseek_thinking_type(params, "disabled") if thinking_effort.to_s == "none"

      params
    end
    private_class_method :effective_custom_params

    def self.custom_thinking_type(custom_params)
      custom_params.dig("thinking", "type").to_s.presence
    end
    private_class_method :custom_thinking_type

    def self.flatten_deepseek_extra_body(params)
      extra_body = params["extra_body"]
      return params unless extra_body.is_a?(Hash)

      params.except("extra_body").deep_merge(extra_body.deep_stringify_keys)
    end
    private_class_method :flatten_deepseek_extra_body

    def self.merge_deepseek_thinking_type(params, type)
      params.deep_merge("thinking" => { "type" => type })
    end
    private_class_method :merge_deepseek_thinking_type

    def self.normalize_custom_params_string(value)
      stripped = value.to_s.strip
      return {} if stripped.blank?

      parsed = JSON.parse(stripped)
      return parsed.deep_stringify_keys if parsed.is_a?(Hash)

      raise InvalidCustomParamsError, "Custom params must be a JSON object"
    rescue JSON::ParserError => e
      raise InvalidCustomParamsError, "must be valid JSON (#{e.message})"
    end
    private_class_method :normalize_custom_params_string
  end
end
