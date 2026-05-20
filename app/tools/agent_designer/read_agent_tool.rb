# frozen_string_literal: true

module AgentDesigner
  READ_AGENT_EDITABLE_FIELDS = [
    "name",
    "description",
    "instructions",
    "agent_type",
    "enabled",
    "selectable",
    "llm_config_source",
    "llm_connector_id",
    "model_id",
    "temperature",
    "thinking_effort",
    "thinking_budget",
    "custom_llm_params",
    "model_routing_config",
    "input_schema",
    "assigned_tool_ids",
    "subagent_ids",
    "skill_catalog_ids",
  ].freeze

  class ReadAgentTool < RubyLLM::Tool
    include AgentLookup

    description "Inspect the current agent configuration or another agent in the current operation."

    param :agent_id,
          desc: "Optional numeric ID or slug. Omit to inspect the current agent from page context.",
          required: false

    def initialize(runtime_context:, current_agent: nil)
      super()
      @runtime_context = runtime_context
      @current_agent = current_agent
    end

    def name = "read_agent"

    def execute(agent_id: nil)
      agent = resolve_agent(agent_id)
      return missing_agent_message if agent.nil?

      render_agent(agent)
    rescue ActiveRecord::RecordNotFound => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error reading agent: #{e.message}"
    end

    private

    def summary_section(agent)
      [
        "## Agent",
        "- ID: `#{agent.id}`",
        "- Name: #{agent.name}",
        "- Slug: `#{agent.slug}`",
        "- Description: #{agent.description.presence || "None"}",
        "- Built-in: #{agent.builtin?}",
        ("- Built-in key: `#{agent.builtin_key}`" if agent.builtin_key.present?),
        "- Agent type: `#{agent.agent_type}`",
        "- Enabled: #{agent.enabled?}",
        "- Selectable: #{agent.selectable?}",
        "- Operation: #{agent.operation.name} (`#{agent.operation.slug}`)",
      ].compact.join("\n")
    end

    def render_agent(agent)
      agent_sections(agent).compact.join("\n\n")
    end

    def agent_sections(agent)
      [
        summary_section(agent),
        llm_section(agent),
        model_routing_section(agent),
        relation_section("Assigned Tools", agent.assigned_tools.order(:name)),
        runtime_tools_section(agent),
        relation_section("Sub-Agents", agent.subagents.order(:name)),
        relation_section("Skill Catalogs", agent.skill_catalogs.order(:name)),
        capabilities_section(agent),
        input_schema_section(agent),
        custom_params_section(agent),
        instructions_section(agent),
        editable_fields_section(agent),
      ]
    end

    def llm_section(agent)
      [
        "## Model Configuration",
        "- LLM source: `#{agent.llm_config_source}`",
        ("- LLM connector ID: `#{agent.llm_connector_id}`" if agent.llm_connector_id.present?),
        ("- Model ID: `#{agent.model_id}`" if agent.model_id.present?),
        "- Temperature: `#{agent.temperature}`",
        ("- Thinking effort: `#{agent.thinking_effort}`" if agent.thinking_effort.present?),
        ("- Thinking budget: `#{agent.thinking_budget}`" if agent.thinking_budget.present?),
      ].compact.join("\n")
    end

    def model_routing_section(agent)
      routing = Llm::ModelRoutingConfig.persistable(agent.model_routing_config)
      if routing.blank?
        return "## Model Routing\n- Single route only (no fallback, canary, or A/B comparison configured)."
      end

      "## Model Routing\n```json\n#{JSON.pretty_generate(routing)}\n```"
    end

    def relation_section(title, relation)
      records = relation.to_a
      return "## #{title}\n- None" if records.empty?

      lines = ["## #{title}"]
      records.each { |record| lines << "- `#{record.id}` — #{record.name}" }
      lines.join("\n")
    end

    def runtime_tools_section(agent)
      tools = agent.runtime_tool_keys
      return "## Built-in Runtime Tools\n- None" if tools.empty?

      lines = ["## Built-in Runtime Tools"]
      tools.each { |tool_key| lines << "- `#{tool_key}`" }
      lines.join("\n")
    end

    def capabilities_section(agent)
      capabilities = agent.configured_capabilities
      if capabilities.empty?
        return [
          "## Capabilities",
          "- None",
          "- Use `list_resources(kind: \"capabilities\")` to discover available capability keys and fields.",
        ].join("\n")
      end

      lines = ["## Capabilities"]
      capabilities.each do |capability|
        summary = capability.respond_to?(:summary) ? capability.summary.to_s.strip : ""
        summary_suffix = summary.present? ? " — #{summary}" : nil
        lines << ["- `#{capability.capability_type}` — #{capability.type_label}", summary_suffix].compact.join
        lines << "  config: `#{JSON.generate(capability.configuration)}`" if capability.configuration.present?
      end
      lines << "- Use `manage_capability` to add, update, or remove capability configs."
      lines.join("\n")
    end

    def input_schema_section(agent)
      schema = agent.input_schema
      return "## Input Schema\n- None" if schema.empty?

      lines = ["## Input Schema"]
      schema.each do |field|
        field_type = field["field_type"].presence || "string"
        requirement = field["required"] ? "required" : "optional"
        config_suffix = field["config"].present? ? " config=#{field["config"].to_json}" : ""
        lines << "- `#{field["variable_name"]}` — #{field["label"]} (#{field_type}, #{requirement})#{config_suffix}"
      end
      lines.join("\n")
    end

    def custom_params_section(agent)
      params = agent.custom_llm_params
      return "## Custom LLM Params\n- None" if params.blank?

      "## Custom LLM Params\n```json\n#{JSON.pretty_generate(params)}\n```"
    end

    def instructions_section(agent)
      rendered_instructions = agent.instructions.to_s.presence || "None"
      "## Instructions\n```text\n#{rendered_instructions}\n```"
    end

    def editable_fields_section(agent)
      [
        "## Editable Attribute Keys",
        *AgentDesigner::READ_AGENT_EDITABLE_FIELDS.map { |field| "- `#{field}`" },
        "- Array and hash fields replace the full stored value on update, so reread first and send the " \
        "complete desired value when changing `input_schema`, `assigned_tool_ids`, `subagent_ids`, " \
        "`skill_catalog_ids`, `custom_llm_params`, or `model_routing_config`.",
        "- Use `manage_record(action: \"clone\", resource: \"agent\", record_id: #{agent.id})` to clone this agent.",
        "- Capability configuration goes through `manage_capability`, not `manage_record`.",
        "- Builtin runtime tools and builtin metadata are read-only in `manage_record`.",
      ].join("\n")
    end
  end
end
