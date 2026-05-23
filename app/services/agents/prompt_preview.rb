# frozen_string_literal: true

module Agents
  class PromptPreview
    STATIC_SAMPLE_VALUES = {
      "number" => 0,
      "number_array" => [0],
      "boolean" => false,
      "boolean_array" => [false],
      "json" => {},
      "date" => "2026-01-01",
      "date_array" => ["2026-01-01"],
      "datetime" => "2026-01-01T00:00:00Z",
      "datetime_array" => ["2026-01-01T00:00:00Z"],
      "file" => "[file]",
      "file_array" => ["[file]"],
    }.freeze

    def initialize(agent, user: nil)
      @agent = agent
      @user = user
    end

    def call
      payload = preview_payload
      payload.merge(digest: Digest::SHA256.hexdigest(JSON.generate(payload.deep_stringify_keys)))
    end

    private

    attr_reader :agent, :user

    def preview_payload
      {
        agent: agent_payload,
        model: model_payload,
        response_format: response_format_payload,
        instructions: rendered_instructions,
        runtime_context: runtime_context_payload,
        inputs: input_payload,
        tools: tools_payload,
        builtin_tools: builtin_tools_payload,
        subagents: subagents_payload,
        skill_catalogs: skill_catalogs_payload,
        capabilities: capabilities_payload,
        prompt_additions: prompt_additions_payload,
      }
    end

    def agent_payload
      {
        id: agent.id,
        name: agent.name,
        type: agent.agent_type,
        enabled: agent.enabled?,
      }
    end

    def model_payload
      connector = agent.resolved_llm_connector
      {
        source: agent.llm_config_source,
        connector: connector&.name,
        provider: connector&.try(:provider_label),
        model_id: agent.resolved_model_id,
        temperature: effective_temperature,
        thinking_effort: effective_thinking_effort,
        thinking_budget: effective_thinking_budget,
        custom_params: effective_custom_params,
        model_routing: effective_model_routing_config,
      }
    end

    def effective_temperature
      system_preference&.configured? ? system_preference.temperature : agent.temperature
    end

    def effective_thinking_effort
      system_preference&.configured? ? system_preference.thinking_effort : agent.thinking_effort
    end

    def effective_thinking_budget
      system_preference&.configured? ? system_preference.thinking_budget : agent.thinking_budget
    end

    def effective_custom_params
      system_preference&.configured? ? system_preference.custom_llm_params : agent.custom_llm_params
    end

    def effective_model_routing_config
      system_preference&.configured? ? system_preference.model_routing_config : agent.model_routing_config
    end

    def system_preference
      return unless agent.llm_config_source == "system_preference"

      @system_preference ||= SystemPreference.current(tenant: agent.tenant)
    end

    def response_format_payload
      {
        format: agent.response_format,
        schema: agent.response_format == "json_schema" ? agent.response_schema : nil,
      }
    end

    def rendered_instructions
      agent.build_full_instructions(user:, input_values: sample_input_values)
    end

    def runtime_context_payload
      {
        note: "Runtime page, channel, mission, and reference context can be appended when the chat is configured.",
      }
    end

    def input_payload
      agent.input_schema.map do |field|
        {
          name: field["variable_name"],
          label: field["label"],
          type: field["field_type"],
          required: field["required"],
          sample: sample_value_for(field),
        }
      end
    end

    def sample_input_values
      agent.input_schema.each_with_object({}) do |field, values|
        name = field["variable_name"].presence
        values[name] = sample_value_for(field) if name
      end
    end

    def sample_value_for(field)
      label = field["label"].presence || field["variable_name"].to_s.humanize
      field_type = field["field_type"].to_s
      return ["Sample #{label}"] if field_type == "string_array"

      STATIC_SAMPLE_VALUES.fetch(field_type, "Sample #{label}")
    end

    def tools_payload
      agent.assigned_tools.enabled.ordered.map do |tool|
        {
          id: tool.id,
          name: tool.name,
          type: tool.tool_type,
        }
      end
    end

    def builtin_tools_payload
      agent.runtime_tool_keys.map do |tool_key|
        definition = BuiltinTools::Registry.definition_for(tool_key)
        {
          key: tool_key,
          name: definition&.name || tool_key,
          description: definition&.description,
          available: definition.present?,
        }
      end
    end

    def subagents_payload
      agent.subagents.enabled.ordered.map do |subagent|
        {
          id: subagent.id,
          name: subagent.name,
          type: subagent.agent_type,
        }
      end
    end

    def skill_catalogs_payload
      agent.skill_catalogs.ordered.map do |catalog|
        {
          id: catalog.id,
          name: catalog.name,
          skills: catalog.skills.size,
        }
      end
    end

    def capabilities_payload
      agent.configured_capabilities.sort_by(&:type_label).map do |capability|
        {
          key: capability.capability_type,
          label: capability.type_label,
        }
      end
    end

    def prompt_additions_payload
      additions = []
      if agent.skill_system_prompt_addition.present?
        additions << { source: "skills", content: agent.skill_system_prompt_addition }
      end
      agent.capability_system_prompt_additions(user:).each do |addition|
        additions << { source: "capability", content: addition }
      end
      additions
    end
  end
end
