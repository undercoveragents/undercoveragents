# frozen_string_literal: true

module BuiltinAgents
  class Definition
    attr_reader :key, :name, :description, :agent_type, :enabled, :temperature,
                :thinking_effort, :llm_config_source, :model_id, :llm_connector_id, :instructions,
                :input_schema, :tool_keys, :subagent_keys, :skill_catalog_keys, :capability_configs,
                :selectable, :source_path

    def initialize(**attributes)
      assign_identity_attributes(attributes)
      assign_runtime_attributes(attributes)
      assign_collection_attributes(attributes)
      @selectable = attributes[:selectable]
      @source_path = Pathname.new(attributes[:source_path])
    end

    alias runtime_tool_keys tool_keys
    alias subagent_builtin_keys subagent_keys
    alias capability_keys capability_configs

    def editable_attributes
      {
        name:,
        description:,
        instructions:,
        enabled:,
        agent_type:,
        temperature:,
        thinking_effort:,
        llm_config_source:,
        model_id:,
        llm_connector_id:,
        input_schema:,
      }
    end

    def locked_attributes
      {
        builtin: true,
        builtin_key: key,
        builtin_source: source_path.to_s,
        runtime_tool_keys: tool_keys,
        selectable:,
      }
    end

    private

    def assign_identity_attributes(attributes)
      @key = attributes[:key].to_s
      @name = attributes[:name].to_s
      @description = attributes[:description].to_s
      @agent_type = attributes[:agent_type].to_s
      @enabled = attributes[:enabled]
    end

    def assign_runtime_attributes(attributes)
      @temperature = attributes[:temperature]
      @thinking_effort = attributes[:thinking_effort].to_s.presence
      @llm_config_source = attributes[:llm_config_source].to_s
      @model_id = attributes[:model_id].presence
      @llm_connector_id = attributes[:llm_connector_id]
      @instructions = attributes[:instructions].to_s
    end

    def assign_collection_attributes(attributes)
      @input_schema = Array(attributes[:input_schema])
      @tool_keys = Array(attributes[:tool_keys]).map(&:to_s)
      @subagent_keys = Array(attributes[:subagent_keys]).map(&:to_s)
      @skill_catalog_keys = Array(attributes[:skill_catalog_keys]).map(&:to_s)
      @capability_configs = normalize_capability_configs(attributes[:capability_configs])
    end

    def normalize_capability_configs(value)
      return {} unless value.is_a?(Hash)

      value.deep_stringify_keys.transform_values do |config|
        config.is_a?(Hash) ? config.deep_stringify_keys : {}
      end
    end
  end
end
