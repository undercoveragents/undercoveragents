# frozen_string_literal: true

module AgentsHelper
  INPUT_PARAMETER_TYPE_LABELS = {
    "string" => "String",
    "string_array" => "String[]",
    "number" => "Number",
    "number_array" => "Number[]",
    "boolean" => "Boolean",
    "boolean_array" => "Boolean[]",
    "file" => "File",
    "file_array" => "File[]",
    "json" => "JSON",
    "date" => "Date",
    "date_array" => "Date[]",
    "datetime" => "DateTime",
    "datetime_array" => "DateTime[]",
  }.freeze

  def agent_origin_badge(agent)
    label = agent.builtin? ? "Built-in" : "User"
    color = agent.builtin? ? "secondary" : "brand"
    content_tag(:span, label, class: "badge badge-#{color} whitespace-nowrap")
  end

  def agent_type_badge(agent)
    content_tag(:span, agent.agent_type.to_s.humanize, class: "badge badge-secondary whitespace-nowrap")
  end

  def agent_status_label(agent)
    agent.enabled? ? "Active" : "Inactive"
  end

  def agent_status_color(agent)
    agent.enabled? ? "success" : "warning"
  end

  def agent_status_badge(agent)
    label = agent_status_label(agent)
    color = agent_status_color(agent)
    content_tag(:span, label, class: "badge badge-#{color} whitespace-nowrap")
  end

  def agent_tool_count_label(agent)
    count = agent.tool_ids.size + agent.runtime_tool_keys.size
    "#{count} #{count == 1 ? "tool" : "tools"}"
  end

  def agent_subagent_count_label(agent)
    count = agent.subagent_ids.size
    "#{count} #{count == 1 ? "sub-agent" : "sub-agents"}"
  end

  def agent_skill_catalog_count_label(agent)
    count = agent.skill_catalog_ids.size
    "#{count} #{count == 1 ? "skill catalog" : "skill catalogs"}"
  end

  def agent_skill_count_label(agent, count = nil)
    count ||= agent.skill_catalogs.sum { |catalog| catalog.skills.size }
    "#{count} #{count == 1 ? "skill" : "skills"}"
  end

  def agent_enabled_capabilities(agent)
    agent.configured_capabilities.sort_by(&:type_label)
  end

  def agent_capability_count_label(agent)
    count = agent_enabled_capabilities(agent).size
    "#{count} #{count == 1 ? "capability" : "capabilities"}"
  end

  def agent_temperature_label(temperature)
    temperature_label(temperature)
  end

  def agent_temperature_color(temperature)
    case temperature
    when 0.0..0.3 then "text-blue-500"
    when 0.3..0.7 then "text-green-500"
    when 0.7..1.2 then "text-amber-500"
    else "text-red-500"
    end
  end

  def agent_model_display(agent_or_model)
    return agent_or_model.presence || "Not configured" unless agent_or_model.is_a?(Agent)

    fallback = {
      "system_preference" => "System preference",
      "runtime" => "Runtime supplied",
    }
    source = agent_or_model.llm_config_source
    model_id = source.in?(fallback.keys) ? agent_or_model.resolved_model_id : agent_or_model.model_id

    model_id.presence || fallback.fetch(source, "Not configured")
  end

  def agent_llm_source_label(agent)
    case agent.llm_config_source
    when "system_preference"
      "System Preference"
    when "runtime"
      "Runtime Supplied"
    else
      "Agent Configuration"
    end
  end

  def agent_llm_connector_display(agent)
    connector = agent.resolved_llm_connector
    return "Not configured" unless connector

    provider = connector.respond_to?(:provider_label) ? connector.provider_label : "LLM"
    "#{connector.name} (#{provider})"
  end

  def agent_input_count_label(agent)
    count = agent.input_schema.size
    "#{count} #{count == 1 ? "input" : "inputs"}"
  end

  def agent_thinking_effort_label(value)
    value.present? ? value.to_s.humanize : "Model Default"
  end

  def agent_thinking_budget_label(value)
    value.present? ? value.to_s : "Automatic"
  end

  def agent_model_routing_label(agent_or_config)
    config = agent_or_config.is_a?(Agent) ? agent_or_config.model_routing_config : agent_or_config
    strategy = config.fetch("strategy", Llm::ModelRoutingConfig::DEFAULT_STRATEGY)

    case strategy
    when "fallback"
      count = Array(config["fallback_models"]).size
      count.positive? ? "Fallback (#{count} alternate #{"model".pluralize(count)})" : "Fallback"
    when "canary"
      percent = config["canary_percent"].presence || "?"
      "Canary (#{percent}%)"
    when "ab_test"
      "A/B Compare"
    else
      "Single Model"
    end
  end

  def agent_input_parameter_type_label(field_type)
    INPUT_PARAMETER_TYPE_LABELS.fetch(field_type.to_s, field_type.to_s.humanize)
  end

  def agent_type_options_for_select(agent = nil)
    agent_type_values_for_select(current_agent_type_value(agent)).map { |type| [type.humanize, type] }
  end

  def models_for_select(models)
    models.map do |model_record|
      [
        model_record.name,
        model_record.model_id,
        { data: { custom_properties: llm_model_option_properties(model_record).to_json } },
      ]
    end
  end

  def llm_connectors_for_select(connectors)
    connectors.to_a.map do |c|
      provider_label = c.respond_to?(:provider_label) ? c.provider_label : "LLM"
      ["#{c.name} (#{provider_label})", c.id]
    end
  end

  # Delegates to the capability configurator's +summary+ method when available,
  # so each capability type owns its own human-readable description.
  def capability_summary(cap)
    config = cap.configurator
    config.respond_to?(:summary) ? config.summary : "Enabled"
  end

  private

  def current_agent_type_value(agent)
    agent.respond_to?(:agent_type) ? agent.agent_type.to_s : agent.to_s
  end

  def agent_type_values_for_select(current_type)
    builtin_agent_types.tap do |types|
      types << current_type if current_type.present? && types.exclude?(current_type)
    end
  end

  def builtin_agent_types
    types = BuiltinAgents::DefinitionLoader.load_all
                                           .map { |definition| definition.agent_type.to_s }
                                           .compact_blank
                                           .uniq
                                           .sort
    types.presence || [AgentConfiguration::DEFAULT_AGENT_TYPE]
  end
end
