# frozen_string_literal: true

module ListResourcesToolCoreResources
  private

  def models(connector_id)
    return "Provide connector_id to list models for a specific connector." if connector_id.blank?

    connector_details = validated_model_connector(connector_id)
    return connector_details if connector_details.is_a?(String)

    connector, provider_key = connector_details
    scope = Model.where(provider: provider_key).picker_projection.order(:name)
    return "No models found for connector `#{connector.id}`." if scope.empty?

    lines = ["## Models for #{connector.name} (`#{connector.id}`)"]
    scope.each do |model_record|
      lines << "- record `#{model_record.id}` — `#{model_record.model_id}` — #{model_record.name}"
    end
    lines.join("\n")
  end

  def validated_model_connector(connector_id)
    connector = ConnectorLookup.find(connector_id, tenant:)
    return "Connector '#{connector_id}' was not found." unless connector

    connector_class = ConnectorPlugin.resolve(connector.connector_type)
    supports_model_listing =
      connector_class.respond_to?(:supports_model_listing?) && connector_class.supports_model_listing?
    return "Connector '#{connector_id}' does not support model listing." unless supports_model_listing

    provider_key = connector_class.model_provider_key(connector) if connector_class.respond_to?(:model_provider_key)
    return "Connector '#{connector_id}' does not expose a provider key." if provider_key.to_s.blank?

    [connector, provider_key]
  end

  def default_models
    pref = SystemPreference.current(tenant:)
    lines = ["## Default Models"]
    lines << "- LLM: connector `#{pref.llm_connector_id}`, model `#{pref.model_id}`" if pref.configured?
    append_default_embedding_model(lines, pref)
    append_default_image_model(lines, pref)
    return "No default models configured. See admin preferences." if lines.size == 1

    lines.join("\n")
  end

  def append_default_embedding_model(lines, pref)
    return unless pref.embedding_configured?

    lines << "- Embedding: connector `#{pref.embedding_connector_id}`, model `#{pref.embedding_model_id}`"
  end

  def append_default_image_model(lines, pref)
    return unless pref.image_configured?

    lines << "- Image: connector `#{pref.image_connector_id}`, model `#{pref.image_model_id}`"
  end

  def tool_types
    types = ToolPlugin.all_types.sort_by { |type| type.fetch(:label) }
    return "No tool types available." if types.empty?

    lines = ["## Tool Types"]
    types.each do |type|
      description = type.fetch(:description).to_s.presence || "No description."
      lines << "- `#{type.fetch(:key)}` — #{type.fetch(:label)} — #{description}"
    end
    lines.join("\n")
  end

  def operations
    scope = tenant.operations.headquarter_first
    return "No operations available." if scope.empty?

    lines = ["## Operations"]
    scope.each { |operation| lines << "- `#{operation.id}` — #{operation.name} (slug: `#{operation.slug}`)" }
    lines.join("\n")
  end

  def users
    scope = tenant.users.order(:email)
    return "No users available." if scope.empty?

    lines = ["## Users"]
    scope.each { |user| lines << "- `#{user.id}` — #{user.email} (#{user.role})" }
    lines.join("\n")
  end

  def tools
    scope = Tool.enabled.ordered
    scope = scope.where(operation: scoped_operation) if scoped_operation
    return "No enabled tools available." if scope.empty?

    lines = ["## Tools (use these IDs in `assigned_tool_ids`)"]
    scope.each do |tool|
      desc = tool.description.to_s.squish.presence || "No description."
      lines << "- `#{tool.id}` — #{tool.name} (#{tool.type_label}) — #{desc}"
    end
    lines.join("\n")
  end

  def runtime_tools
    definitions = BuiltinTools::Registry.user_assignable_definitions
    return "No user-assignable built-in runtime tools available." if definitions.empty?

    lines = ["## Built-in Runtime Tools (use these keys in `runtime_tool_keys`)"]
    definitions.each do |definition|
      desc = definition.description.to_s.squish.presence || "No description."
      hint = definition.configuration_hint.to_s.squish.presence
      lines << [
        "- `#{definition.key}` — #{definition.name} — #{desc}",
        ("Configuration: #{hint}" if hint),
      ].compact.join(" — ")
    end
    lines.join("\n")
  end

  def agents
    scope = Agent.enabled.selectable
    scope = scope.where(operation: scoped_operation) if scoped_operation
    scope = scope.where.not(id: @current_agent.id) if @current_agent
    scope = scope.ordered
    return "No agents configured." if scope.empty?

    lines = ["## Agents (use these IDs in `subagent_ids`)"]
    scope.each { |agent| lines << "- `#{agent.id}` — #{agent.name}" }
    lines.join("\n")
  end

  def missions
    scope = tenant.missions.order(:name)
    scope = scope.where.not(id: @mission.id) if @mission
    return "No other missions available." if scope.empty?

    lines = ["## Missions (for sub-mission nodes)"]
    scope.each { |mission| lines << "- `#{mission.id}` — #{mission.name}" }
    lines.join("\n")
  end

  def channels
    scope = scoped_operation ? scoped_operation.channels.order(:name) : Channel.none
    return "No channels available." if scope.empty?

    lines = ["## Channels"]
    scope.each { |channel| lines << "- `#{channel.id}` — #{channel.name} (#{channel.type_label})" }
    lines.join("\n")
  end

  def clients
    scope = scoped_operation ? scoped_operation.channels.by_type("client").order(:name) : Channel.none
    return "No clients available." if scope.empty?

    lines = ["## Clients"]
    scope.each { |channel| lines << "- `#{channel.id}` — #{channel.name}" }
    lines.join("\n")
  end

  def skill_catalogs
    scope = SkillCatalog.order(:name)
    scope = scope.where(operation: scoped_operation) if scoped_operation
    return "No skill catalogs available." if scope.empty?

    lines = ["## Skill Catalogs (use these IDs in `skill_catalog_ids`)"]
    scope.each { |catalog| lines << "- `#{catalog.id}` — #{catalog.name}" }
    lines.join("\n")
  end

  def skills
    return "No skills available." unless scoped_operation

    scope = Skill.joins(:skill_catalog).where(skill_catalogs: { operation_id: scoped_operation.id }).order(:name)
    return "No skills available." if scope.empty?

    lines = ["## Skills"]
    scope.each { |skill| lines << "- `#{skill.id}` — #{skill.name} (#{skill.skill_catalog.name})" }
    lines.join("\n")
  end

  def rag_flows
    scope = RagFlow.order(:name)
    scope = scope.where(operation: scoped_operation) if scoped_operation
    scope = scope.joins(:operation).where(operations: { tenant_id: tenant.id }) if scoped_operation.blank? && tenant
    return "No RAG flows available." if scope.empty?

    lines = ["## RAG Flows"]
    scope.each { |flow| lines << "- `#{flow.id}` — #{flow.name}" }
    lines.join("\n")
  end

  def connectors
    scope = tenant.connectors.ordered
    return "No connectors available." if scope.empty?

    lines = ["## Connectors"]
    scope.each do |connector|
      status = connector.enabled? ? "enabled" : "disabled"
      lines << "- `#{connector.id}` — #{connector.name} (#{connector.type_label}) — #{status}"
    end
    lines.join("\n")
  end

  def test_suites
    scope = tenant_scoped_test_suites
    return "No test suites available." if scope.empty?

    lines = ["## Test Suites"]
    scope.each do |test_suite|
      target = test_suite.agent&.name || test_suite.mission&.name
      detail = [test_suite.suite_type, target].compact.join(" — ")
      lines << test_suite_summary_line(test_suite, detail)
    end
    lines.join("\n")
  end

  def agent_types
    types = BuiltinAgents::DefinitionLoader.load_all
                                           .map { |definition| definition.agent_type.to_s }
                                           .compact_blank
                                           .uniq
                                           .sort
    return "No agent types available." if types.empty?

    lines = ["## Agent Types"]
    types.each { |type| lines << "- `#{type}`" }
    lines.join("\n")
  end

  def capabilities = AgentDesigner::CapabilityCatalog.render
end
