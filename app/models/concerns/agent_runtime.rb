# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength
module AgentRuntime
  extend ActiveSupport::Concern

  def playground_compatible?
    runtime_tool_keys.empty?
  end

  def tools(parent_chat: nil, runtime_context: {})
    assigned_tool_instances = Tools::RuntimeBuilder.build_many(assigned_tools.enabled, agent: self, parent_chat:)
    runtime_tools = build_runtime_tools(parent_chat:, runtime_context:)
    subagent_tools = build_subagent_tools(parent_chat:, runtime_context:)

    assigned_tool_instances + prioritized_runtime_tools(runtime_tools, subagent_tools) + skill_tools +
      capability_tools(parent_chat:)
  end

  def ask(question, **)
    build_chat(**).ask(question)
  end

  def build_full_instructions(user: nil, input_values: {})
    rendered_instructions = Agents::InstructionRenderer.render(
      instructions,
      agent: self,
      user:,
      input_values:,
    )

    parts = [rendered_instructions.presence, skill_system_prompt_addition.presence]
    parts.concat(capability_system_prompt_additions(user:))
    parts.compact.join("\n\n")
  end

  def build_chat(**options)
    runtime_options = normalized_runtime_options(options)
    runtime_config = resolve_runtime_configuration(
      model_id: runtime_options[:model_id],
      temperature: runtime_options[:temperature],
      llm_context: runtime_options[:llm_context],
      runtime_context: runtime_options[:runtime_context],
    )
    chat = create_runtime_chat(runtime_options, runtime_config)

    configure_chat(chat, **resolved_configure_options(runtime_options, runtime_config))
    chat
  end

  def configure_chat(chat, **options)
    runtime_options = normalized_runtime_options(options)
    runtime_config = resolve_runtime_configuration(
      model_id: runtime_options[:model_id],
      temperature: runtime_options[:temperature],
      llm_context: runtime_options[:llm_context],
      runtime_context: runtime_options[:runtime_context],
    )
    combined_tools = combined_chat_tools(chat, runtime_options)

    apply_chat_runtime_config(chat, runtime_config, combined_tools)
    apply_chat_instructions(chat, runtime_options)
    chat.with_tools(*combined_tools) if combined_tools.any?
    chat
  end

  private

  def normalized_runtime_options(options)
    {
      parent_chat: nil,
      execution_context: nil,
      user: nil,
      title: nil,
      model_id: nil,
      temperature: self.class::UNSET,
      llm_context: self.class::UNSET,
      input_values: {},
      runtime_context: {},
      extra_tools: [],
    }.merge(options)
  end

  def build_runtime_tools(parent_chat:, runtime_context: {})
    runtime_tool_keys.filter_map do |tool_key|
      build_runtime_tool(tool_key, parent_chat:, runtime_context:)
    end
  end

  def build_subagent_tools(parent_chat:, runtime_context: {})
    subagents.enabled.filter_map do |subagent|
      SubagentTool.for_agent(subagent, parent_chat:, runtime_context:)
    rescue StandardError => e
      Rails.logger.error "[Agent] Failed to build tool for subagent '#{subagent.name}': #{e.message}"
      nil
    end
  end

  def build_runtime_tool(tool_key, parent_chat:, runtime_context: {})
    BuiltinTools::Registry.build(tool_key, agent: self, parent_chat:, **runtime_context)
  rescue StandardError => e
    rebuild_runtime_tool_after_registry_refresh(tool_key, parent_chat:, runtime_context:, initial_error: e)
  end

  def rebuild_runtime_tool_after_registry_refresh(tool_key, parent_chat:, initial_error:, runtime_context: {})
    BuiltinTools::Registrations.register_all!
    BuiltinTools::Registry.build(tool_key, agent: self, parent_chat:, **runtime_context)
  rescue StandardError => e
    Rails.logger.error(
      "[Agent] Failed to build runtime tool '#{tool_key}' for '#{name}': #{e.message} " \
      "(initial error: #{initial_error.message})",
    )
    nil
  end

  def prioritized_runtime_tools(runtime_tools, subagent_tools)
    return runtime_tools + subagent_tools unless builtin_key == "agent_alpha"

    subagent_tools + runtime_tools
  end

  def create_runtime_chat(options, runtime_config)
    parent_chat = options[:parent_chat]
    user = options[:user] || parent_chat&.user

    Chat.create!(
      agent: self,
      model: runtime_config[:model_record],
      parent_chat:,
      user:,
      title: options[:title].presence || "Subagent: #{name}",
      execution_context: options[:execution_context] || parent_chat&.execution_context || :user,
    )
  end

  def resolved_configure_options(options, runtime_config)
    options.merge(
      user: options[:user] || options[:parent_chat]&.user,
      model_id: runtime_config[:model_id],
      temperature: runtime_config[:temperature],
      llm_context: runtime_config.fetch(:context, nil),
    )
  end

  def combined_chat_tools(chat, options)
    agent_tools = tools(parent_chat: chat, runtime_context: options[:runtime_context])
    agent_tools + Array(options[:extra_tools]).compact
  end

  def apply_chat_runtime_config(chat, runtime_config, combined_tools)
    chat.context = runtime_config[:context] if runtime_config.key?(:context)
    chat.with_model(runtime_config[:model_id]) if runtime_config[:model_id].present?
    apply_runtime_llm_options(chat, runtime_config, combined_tools)
    attach_model_routing(chat, runtime_config, combined_tools)
  end

  def apply_chat_instructions(chat, options)
    full_instructions = build_full_instructions(user: options[:user], input_values: options[:input_values])
    runtime_instructions = Agents::RuntimeContextInstructions.new(options[:runtime_context]).build

    chat.with_instructions(full_instructions) if full_instructions.present?
    chat.with_runtime_instructions(runtime_instructions) if runtime_instructions.present?
  end

  def resolve_runtime_configuration(model_id:, temperature:, llm_context:, runtime_context: {})
    preference = system_preference_runtime? ? SystemPreference.current(tenant:) : nil
    selected_model_id = select_runtime_model_id(model_id, preference)
    require_runtime_model!(selected_model_id)

    {
      model_id: selected_model_id,
      model_record: Llm::ChatOptions.resolve_model(selected_model_id),
      temperature: select_runtime_temperature(temperature, preference),
      context: select_runtime_context(llm_context, preference),
      connector: select_runtime_connector(preference),
    }.merge(runtime_llm_options(preference)).merge(runtime_llm_overrides(runtime_context))
  end

  def select_runtime_model_id(model_id, preference)
    return model_id if model_id.present?
    return system_preference_model_id(preference) if system_preference_runtime?

    self.model_id
  end

  def system_preference_model_id(preference)
    raise_system_preference_error unless preference&.configured?

    preference.model_id
  end

  def require_runtime_model!(selected_model_id)
    return unless llm_config_source == "runtime" && selected_model_id.blank?

    raise "Agent '#{name}' requires runtime LLM configuration, but no model_id was provided."
  end

  def select_runtime_context(llm_context, preference)
    return llm_context unless llm_context.equal?(self.class::UNSET)

    default_runtime_context(preference)
  end

  def select_runtime_temperature(temperature, preference)
    return temperature unless temperature.equal?(self.class::UNSET)
    return preference.temperature if preference&.configured?

    self.temperature
  end

  def runtime_llm_options(preference)
    options =
      if preference&.configured?
        preference.llm_runtime_settings.slice(
          :thinking_effort,
          :thinking_budget,
          :custom_params,
          :model_routing_config,
        )
      else
        {
          thinking_effort:,
          thinking_budget:,
          custom_params: custom_llm_params,
          model_routing_config:,
        }
      end

    options.merge(response_format:, response_schema:)
  end

  def runtime_llm_overrides(runtime_context)
    return {} unless runtime_context.respond_to?(:to_h)

    llm_config = runtime_context.to_h.deep_stringify_keys["llm_config"]
    return {} unless llm_config.is_a?(Hash)
    return {} unless llm_config.key?("thinking_effort")

    effort = llm_config["thinking_effort"].to_s.presence
    unless effort.blank? || effort.in?(Llm::ChatOptions::THINKING_EFFORTS)
      raise ArgumentError, "Thinking effort is invalid"
    end

    { thinking_effort: effort, thinking_budget: nil }
  end

  def system_preference_runtime?
    llm_config_source == "system_preference"
  end

  def default_runtime_context(preference)
    return default_system_preference_context(preference) if system_preference_runtime?

    resolve_llm_context
  end

  def default_system_preference_context(preference)
    raise_system_preference_error unless preference&.configured?

    preference.resolve_llm_context
  end

  def select_runtime_connector(preference)
    return preference.llm_connector if system_preference_runtime?

    llm_connector
  end

  def resolved_runtime_connector(runtime_config)
    return runtime_config[:connector] if runtime_config[:connector].present?

    if system_preference_runtime?
      preference = SystemPreference.current(tenant:)
      return preference.llm_connector if preference&.configured?
    end

    llm_connector
  end

  def apply_runtime_llm_options(chat, runtime_config, combined_tools)
    Llm::ChatOptions.apply_to_chat(
      chat:,
      model_id: runtime_config[:model_id],
      model_record: runtime_config[:model_record],
      tools_present: combined_tools.any?,
      temperature: runtime_config[:temperature],
      thinking_effort: runtime_config[:thinking_effort],
      thinking_budget: runtime_config[:thinking_budget],
      custom_params: runtime_config[:custom_params],
      response_format: runtime_config[:response_format],
      response_schema: runtime_config[:response_schema],
    )
  end

  def attach_model_routing(chat, runtime_config, combined_tools)
    routing_config = runtime_config[:model_routing_config]
    return if Llm::ModelRoutingConfig.persistable(routing_config).blank?

    chat.configure_model_routing!(
      primary_connector: resolved_runtime_connector(runtime_config),
      primary_model_id: runtime_config[:model_id],
      primary_model_record: runtime_config[:model_record],
      routing_config:,
      temperature: runtime_config[:temperature],
      thinking_effort: runtime_config[:thinking_effort],
      thinking_budget: runtime_config[:thinking_budget],
      custom_params: runtime_config[:custom_params],
      response_format: runtime_config[:response_format],
      response_schema: runtime_config[:response_schema],
      tools_present: combined_tools.any?,
    )
  end

  def raise_system_preference_error
    raise "Default model is not configured. Please set it in Settings → Preferences."
  end

  def build_tool_for(tool_record, parent_chat: nil)
    Tools::RuntimeBuilder.build(tool_record, agent: self, parent_chat:)
  end
end
# rubocop:enable Metrics/ModuleLength
