# frozen_string_literal: true

module Missions
  class LlmNodeRuntimeConfig
    Resolved = Data.define(
      :source,
      :connector,
      :model_id,
      :model_record,
      :temperature,
      :thinking_effort,
      :thinking_budget,
      :custom_params,
      :model_routing_config,
    )

    NODE_SOURCE = "node"
    SYSTEM_SOURCE = "system_preference"
    RUNTIME_SOURCE = "runtime"
    SOURCES = [NODE_SOURCE, SYSTEM_SOURCE, RUNTIME_SOURCE].freeze
    RUNTIME_CONFIG_KEYS = ["_llm_config", "llm_config"].freeze

    def self.source_for(node_data)
      data = (node_data || {}).to_h.deep_stringify_keys
      source = data["llm_config_source"].presence
      return source if source.present?
      return NODE_SOURCE if data["connector_id"].present? || data["model"].present?

      SYSTEM_SOURCE
    end

    def self.valid_source?(source)
      source.to_s.in?(SOURCES)
    end

    def self.resolve(node_data:, context:)
      new(node_data:, context:).resolve
    end

    def initialize(node_data:, context:)
      @node_data = (node_data || {}).to_h.deep_stringify_keys
      @context = context
    end

    def resolve
      source = self.class.source_for(node_data)
      return [nil, "LLM source is invalid"] unless self.class.valid_source?(source)

      settings = settings_for(source)
      connector = resolve_connector(settings[:connector_id])
      return [nil, "LLM connector not configured"] unless connector

      model_id = settings[:model_id].presence
      return [nil, "LLM model not configured"] if model_id.blank?

      [resolved_config(source, connector, model_id, settings), nil]
    end

    private

    attr_reader :context, :node_data

    def settings_for(source)
      return node_settings if source == NODE_SOURCE
      return system_preference_settings if source == SYSTEM_SOURCE

      runtime_settings
    end

    def node_settings
      {
        connector_id: node_data["connector_id"],
        model_id: node_data["model"],
        temperature: node_data.key?("temperature") ? node_data["temperature"] : SystemPreference::DEFAULT_TEMPERATURE,
        thinking_effort: node_data["thinking_effort"],
        thinking_budget: node_data["thinking_budget"],
        custom_params: node_data["custom_llm_params"],
        model_routing_config: node_data["model_routing_config"],
      }
    end

    def system_preference_settings
      preference = system_preference
      return {} unless preference&.configured?

      preference.llm_runtime_settings
    end

    def runtime_settings
      base = system_preference_settings
      runtime = normalize_runtime_settings(runtime_config_payload)
      base.merge(runtime) { |_key, old_value, new_value| new_value.presence || old_value }
    end

    def runtime_config_payload
      RUNTIME_CONFIG_KEYS.each do |key|
        value = context.get_variable(key)
        return value if value.present?
      end

      trigger_data = context.get_variable("_trigger_data")
      return unless trigger_data.respond_to?(:[])

      RUNTIME_CONFIG_KEYS.filter_map { |key| trigger_data[key] }.first
    end

    def normalize_runtime_settings(value)
      raw = parse_runtime_config(value)
      return {} unless raw.is_a?(Hash)

      data = raw.deep_stringify_keys
      {
        connector_id: data["connector_id"].presence || data["llm_connector_id"].presence,
        model_id: data["model"].presence || data["model_id"].presence,
        temperature: data["temperature"],
        thinking_effort: data["thinking_effort"],
        thinking_budget: data["thinking_budget"],
        custom_params: data["custom_llm_params"].presence || data["custom_params"],
        model_routing_config: data["model_routing_config"].presence || data["model_routing"],
      }.compact
    end

    def parse_runtime_config(value)
      return JSON.parse(value) if value.is_a?(String)
      return value.to_h if value.respond_to?(:to_h)

      nil
    rescue JSON::ParserError
      nil
    end

    def system_preference
      return if tenant.blank?

      @system_preference ||= SystemPreference.current(tenant:)
    end

    def tenant
      mission = context.mission_run&.mission
      mission&.operation&.tenant
    end

    def resolve_connector(connector_id)
      return if tenant.blank?

      ConnectorLookup.find(connector_id, tenant:)
    end

    def resolved_config(source, connector, model_id, settings)
      Resolved.new(
        source:,
        connector:,
        model_id:,
        model_record: Llm::ChatOptions.resolve_model(model_id),
        temperature: settings[:temperature],
        thinking_effort: settings[:thinking_effort],
        thinking_budget: settings[:thinking_budget],
        custom_params: settings[:custom_params],
        model_routing_config: settings[:model_routing_config],
      )
    end
  end
end
