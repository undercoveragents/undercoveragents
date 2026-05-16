# frozen_string_literal: true

module SubagentToolInputValues
  private

  def derived_input_values
    schema_variables = @agent.input_schema.filter_map { |field| field["variable_name"].presence }
    return {} if schema_variables.empty?

    {}.tap do |values|
      values.merge!(mission_input_values(schema_variables))
      values.merge!(agent_input_values(schema_variables))
      values.merge!(test_suite_input_values(schema_variables))
      values.merge!(channel_input_values(schema_variables))
      values.merge!(client_input_values(schema_variables))
      values.merge!(skill_catalog_input_values(schema_variables))
      values.merge!(tool_input_values(schema_variables))
    end.compact_blank
  end

  def mission_input_values(schema_variables)
    mission = @runtime_context[:mission]
    return {} unless mission.is_a?(Mission)

    {}.tap do |values|
      values[:mission_name] = mission.name if schema_variables.include?("mission_name")
      values[:mission_description] = mission.description.to_s if schema_variables.include?("mission_description")
    end
  end

  def agent_input_values(schema_variables)
    current_agent = @runtime_context[:current_agent]
    return {} unless current_agent.is_a?(Agent)

    {}.tap do |values|
      values[:agent_name] = current_agent.name if schema_variables.include?("agent_name")
      values[:agent_description] = current_agent.description.to_s if schema_variables.include?("agent_description")
    end
  end

  def test_suite_input_values(schema_variables)
    current_test_suite = @runtime_context[:current_test_suite]
    return {} unless current_test_suite.is_a?(TestSuite)

    {}.tap do |values|
      values[:test_suite_name] = current_test_suite.name if schema_variables.include?("test_suite_name")
      if schema_variables.include?("test_suite_description")
        values[:test_suite_description] = current_test_suite.description.to_s
      end
      values[:test_suite_type] = current_test_suite.suite_type if schema_variables.include?("test_suite_type")
    end
  end

  def tool_input_values(schema_variables)
    current_tool = @runtime_context[:current_tool]
    return {} unless current_tool.is_a?(Tool)

    {}.tap do |values|
      values[:tool_name] = current_tool.name if schema_variables.include?("tool_name")
      values[:tool_description] = current_tool.description.to_s if schema_variables.include?("tool_description")
      values[:tool_type] = current_tool.tool_type if schema_variables.include?("tool_type")
      values[:tool_type_label] = current_tool.type_label if schema_variables.include?("tool_type_label")
    end
  end

  def channel_input_values(schema_variables)
    current_channel = @runtime_context[:current_channel]
    return {} unless current_channel.is_a?(Channel)

    requested_keys = schema_variables.map(&:to_sym)
    values = {
      channel_name: current_channel.name,
      channel_type: current_channel.channel_type,
    }
    resolved_title = resolved_channel_title(current_channel)
    values[:channel_title] = resolved_title if resolved_title.present?

    values.slice(*requested_keys)
  end

  def resolved_channel_title(current_channel)
    settings_payload = current_channel.settings_payload || {}

    settings_payload["title"].presence || current_channel.try(:title).to_s.presence
  end

  def client_input_values(schema_variables)
    current_client = @runtime_context[:current_client]
    return {} unless current_client.is_a?(Client)

    {}.tap do |values|
      values[:client_name] = current_client.name if schema_variables.include?("client_name")
      values[:client_title] = current_client.title.to_s if schema_variables.include?("client_title")
    end
  end

  def skill_catalog_input_values(schema_variables)
    current_skill_catalog = @runtime_context[:current_skill_catalog]
    return {} unless current_skill_catalog.is_a?(SkillCatalog)

    {}.tap do |values|
      values[:skill_catalog_name] = current_skill_catalog.name if schema_variables.include?("skill_catalog_name")
      if schema_variables.include?("skill_catalog_description")
        values[:skill_catalog_description] = current_skill_catalog.description.to_s
      end
    end
  end

  def inherited_model_id
    @parent_chat&.model&.model_id.presence || @parent_chat&.agent&.resolved_model_id.presence
  end

  def inherited_llm_context
    return unless @parent_chat

    @parent_chat.context.presence || @parent_chat.agent&.resolve_llm_context
  end
end
