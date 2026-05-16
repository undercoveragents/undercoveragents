# frozen_string_literal: true

require "rails_helper"

RSpec.describe BuiltinAgents::Definition do
  def build_definition(capability_configs: {})
    described_class.new(
      key: "demo",
      name: "Demo",
      description: "Demo definition",
      agent_type: "general",
      enabled: true,
      temperature: 0.7,
      thinking_effort: nil,
      llm_config_source: AgentConfiguration::DEFAULT_LLM_CONFIG_SOURCE,
      model_id: nil,
      llm_connector_id: nil,
      instructions: "",
      input_schema: [],
      tool_keys: [],
      subagent_keys: [],
      skill_catalog_keys: [],
      capability_configs:,
      selectable: false,
      source_path: Rails.root.join("config/builtin_agents/demo.toml"),
    )
  end

  it "falls back to an empty capability map when capability configs are not a hash" do
    definition = build_definition(capability_configs: [])

    expect(definition.capability_configs).to eq({})
  end

  it "normalizes non-hash capability entries to empty hashes" do
    definition = build_definition(capability_configs: { chat_title_generator: "invalid" })

    expect(definition.capability_configs).to eq("chat_title_generator" => {})
  end
end
