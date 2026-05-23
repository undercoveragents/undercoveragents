# frozen_string_literal: true

module Llm
  class ChatOptions
    class InvalidCustomParamsError < ArgumentError; end

    THINKING_EFFORTS = ["none", "low", "medium", "high"].freeze

    def self.reasoning_available?(model_record:)
      return true if model_record.nil?

      model_record.supports_reasoning? != false
    end

    def self.apply_to_chat(chat:, model_id:, model_record: nil, tools_present: false, **settings)
      resolved_model = model_record || resolve_model(model_id)
      thinking_settings = {
        effort: settings[:thinking_effort],
        budget: settings[:thinking_budget],
      }
      custom_params = provider_disabled_thinking_params(
        normalize_custom_params(settings[:custom_params]),
        resolved_model,
        thinking_settings[:effort],
      )

      apply_temperature(chat, settings[:temperature], resolved_model)
      apply_thinking(chat, resolved_model, thinking_settings, tools_present:)
      apply_custom_params(chat, custom_params)
      apply_response_format(chat, settings[:response_format], settings[:response_schema])

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

    def self.apply_thinking(chat, model_record, thinking_settings, **_options)
      options = thinking_options(**thinking_settings)
      return if options.blank?
      return unless reasoning_available?(model_record:)

      chat.with_thinking(**options)
    end
    private_class_method :apply_thinking

    def self.apply_custom_params(chat, custom_params)
      return if custom_params.blank?

      chat.with_params(**custom_params.deep_symbolize_keys)
    end
    private_class_method :apply_custom_params

    def self.apply_response_format(chat, response_format, response_schema)
      Llm::ResponseFormat.apply_to_chat(chat:, response_format:, response_schema:)
    end
    private_class_method :apply_response_format

    def self.provider_disabled_thinking_params(custom_params, model_record, thinking_effort)
      return custom_params unless thinking_effort.to_s == "none"
      return custom_params unless model_record&.provider.to_s == "deepseek"

      custom_params.deep_merge("thinking" => { "type" => "disabled" })
    end
    private_class_method :provider_disabled_thinking_params

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
