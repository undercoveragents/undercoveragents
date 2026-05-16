# frozen_string_literal: true

module Admin
  module AgentDefaultAttributes
    private

    def default_agent_attributes(prefs = SystemPreference.current_settings(tenant: current_tenant))
      {
        agent_type: AgentConfiguration::DEFAULT_AGENT_TYPE,
        temperature: Agent::DEFAULT_TEMPERATURE,
        enabled: true,
        llm_config_source: "system_preference",
        llm_connector_id: prefs[:llm_connector_id],
        model_id: prefs[:model_id],
      }
    end
  end
end
