# frozen_string_literal: true

module Agents
  class InstructionRenderer
    TEMPLATE_PATTERN = /\{\{\s*([a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)\s*\}\}/
    MISSING = Object.new

    def self.render(template, agent: nil, user: nil, input_values: {})
      return "" if template.blank?

      values = input_schema_defaults(agent).merge(normalize_hash(input_values)).merge(default_context(agent:, user:))
      template.gsub(TEMPLATE_PATTERN) do
        value = resolve_token(values, Regexp.last_match(1))
        value.equal?(MISSING) ? Regexp.last_match(0) : format_value(value)
      end
    end

    def self.input_schema_defaults(agent)
      return {} unless agent

      agent.input_schema.filter_map { |field| field["variable_name"].presence }.index_with { "" }
    end
    private_class_method :input_schema_defaults

    def self.default_context(agent:, user:)
      {}.tap do |context|
        if agent
          context["agent"] = {
            "id" => agent.id,
            "name" => agent.name,
            "agent_type" => agent.agent_type,
            "builtin" => agent.builtin?,
          }
        end

        if user
          context["user"] = {
            "id" => user.id,
            "email" => user.email,
          }
        end
      end
    end
    private_class_method :default_context

    def self.normalize_hash(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, val), hash|
          hash[key.to_s] = normalize_hash(val)
        end
      when Array
        value.map { |item| normalize_hash(item) }
      when ActiveRecord::Base
        normalize_hash(value.as_json)
      else
        value
      end
    end
    private_class_method :normalize_hash

    def self.resolve_token(values, token)
      token.split(".").reduce(values) do |current, part|
        case current
        when Hash
          return MISSING unless current.key?(part)

          current[part]
        else
          return MISSING unless current.respond_to?(part)

          current.public_send(part)
        end
      end
    end
    private_class_method :resolve_token

    def self.format_value(value)
      case value
      when nil
        ""
      when Hash, Array
        JSON.pretty_generate(value)
      else
        value.to_s
      end
    end
    private_class_method :format_value
  end
end
