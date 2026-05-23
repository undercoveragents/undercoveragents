# frozen_string_literal: true

module Llm
  class ResponseFormat
    class InvalidSchemaError < ArgumentError; end

    JSON_OBJECT_PARAM = { "response_format" => { "type" => "json_object" } }.freeze

    def self.normalize_format(value)
      value.to_s.presence || AgentConfiguration::DEFAULT_RESPONSE_FORMAT
    end

    def self.normalize_schema(value)
      case value
      when nil
        {}
      when String
        normalize_schema_string(value)
      when Hash
        value.deep_stringify_keys
      else
        return value.to_h.deep_stringify_keys if value.respond_to?(:to_h)

        raise InvalidSchemaError, "Response schema must be a JSON object"
      end
    end

    def self.apply_to_chat(chat:, response_format:, response_schema:)
      case normalize_format(response_format)
      when "json_object"
        apply_json_object(chat)
      when "json_schema"
        apply_json_schema(chat, response_schema)
      end
    end

    def self.schema_json(value)
      schema = normalize_schema(value)
      schema.present? ? JSON.pretty_generate(schema) : ""
    rescue InvalidSchemaError, JSON::JSONError
      value.to_s
    end

    def self.schema_summary(schema)
      normalized = normalize_schema(schema)
      return "No schema" if normalized.blank?

      type = normalized["type"].presence || "object"
      properties = normalized["properties"].is_a?(Hash) ? normalized["properties"].keys : []
      return "#{type} schema" if properties.empty?

      "#{type} schema (#{properties.size} #{"field".pluralize(properties.size)})"
    rescue InvalidSchemaError
      "Invalid schema"
    end

    def self.normalize_schema_string(value)
      stripped = value.to_s.strip
      return {} if stripped.blank?

      parsed = JSON.parse(stripped)
      raise InvalidSchemaError, "Response schema must be a JSON object" unless parsed.is_a?(Hash)

      parsed.deep_stringify_keys
    rescue JSON::ParserError => e
      raise InvalidSchemaError, "Response schema must be valid JSON (#{e.message})"
    end
    private_class_method :normalize_schema_string

    def self.apply_json_object(chat)
      params = existing_params(chat).deep_merge(JSON_OBJECT_PARAM)
      chat.with_params(**params.deep_symbolize_keys)
    end
    private_class_method :apply_json_object

    def self.apply_json_schema(chat, response_schema)
      chat.with_schema(normalize_schema(response_schema))
    end
    private_class_method :apply_json_schema

    def self.existing_params(chat)
      return {} unless chat.respond_to?(:params)

      params = chat.params
      params.respond_to?(:to_h) ? params.to_h.deep_stringify_keys : {}
    end
    private_class_method :existing_params
  end
end
