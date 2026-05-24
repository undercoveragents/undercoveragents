# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentsHelper do
  describe "#agent_origin_badge" do
    it "returns a built-in badge for builtin agents" do
      agent = build(:agent, builtin: true, builtin_key: "code_assistant")

      badge = helper.agent_origin_badge(agent)
      expect(badge).to include("Built-in")
      expect(badge).to include("badge-secondary")
    end

    it "returns a user badge for non-builtin agents" do
      agent = build(:agent, builtin: false)

      badge = helper.agent_origin_badge(agent)
      expect(badge).to include("User")
      expect(badge).to include("badge-brand")
    end
  end

  describe "#agent_type_badge" do
    it "renders the humanized agent type" do
      agent = build(:agent, agent_type: "mission_designer")

      expect(helper.agent_type_badge(agent)).to include("Mission designer")
    end
  end

  describe "#agent_status_label" do
    it "returns 'Active' for enabled agents" do
      agent = build(:agent, enabled: true)
      expect(helper.agent_status_label(agent)).to eq("Active")
    end

    it "returns 'Inactive' for disabled agents" do
      agent = build(:agent, enabled: false)
      expect(helper.agent_status_label(agent)).to eq("Inactive")
    end
  end

  describe "#agent_status_color" do
    it "returns 'success' for enabled agents" do
      agent = build(:agent, enabled: true)
      expect(helper.agent_status_color(agent)).to eq("success")
    end

    it "returns 'warning' for disabled agents" do
      agent = build(:agent, enabled: false)
      expect(helper.agent_status_color(agent)).to eq("warning")
    end
  end

  describe "#agent_status_badge" do
    it "returns a badge span with the correct class" do
      agent = build(:agent, enabled: true)
      badge = helper.agent_status_badge(agent)
      expect(badge).to include("badge-success")
      expect(badge).to include("Active")
    end

    it "returns a warning badge for disabled agents" do
      agent = build(:agent, enabled: false)
      badge = helper.agent_status_badge(agent)
      expect(badge).to include("badge-warning")
      expect(badge).to include("Inactive")
    end
  end

  describe "#agent_tool_count_label" do
    it "returns singular for one tool" do
      agent = create(:agent, :with_sql_tool)

      expect(helper.agent_tool_count_label(agent)).to eq("1 tool")
    end

    it "returns plural for multiple tools" do
      agent = create(:agent)
      connector1 = create(:connector, :sql_database, :enabled)
      connector2 = create(:connector, :sql_database, :enabled)
      sq1 = create(:tools_sql_query, connector: connector1)
      sq2 = create(:tools_sql_query, connector: connector2)
      tool1 = create(:tool, :enabled, toolable: sq1)
      tool2 = create(:tool, :enabled, toolable: sq2)
      agent.update!(tool_ids: [tool1.id, tool2.id])

      expect(helper.agent_tool_count_label(agent)).to eq("2 tools")
    end

    it "returns zero tools when none exist" do
      agent = create(:agent)
      expect(helper.agent_tool_count_label(agent)).to eq("0 tools")
    end

    it "counts built-in runtime tools" do
      agent = create(:agent)
      agent.runtime_tool_keys = ["mission_designer.read_flow"]

      expect(helper.agent_tool_count_label(agent)).to eq("1 tool")
    end
  end

  describe "#agent_type_options_for_select" do
    it "returns options derived from builtin agent definitions" do
      options = helper.agent_type_options_for_select

      expect(options).to include(["Mission designer", "mission_designer"])
      expect(options).to include(["Sql query", "sql_query"])
    end

    it "preserves the current type even when its builtin definition no longer exists" do
      agent = build(:agent, agent_type: "expression_writer")

      options = helper.agent_type_options_for_select(agent)

      expect(options.count { |label, value| label == "Expression writer" && value == "expression_writer" }).to eq(1)
    end

    it "preserves the current type when it is not part of builtin definitions" do
      agent = build(:agent, agent_type: "custom_specialist")

      expect(helper.agent_type_options_for_select(agent)).to include(["Custom specialist", "custom_specialist"])
    end

    it "does not duplicate builtin agent types in the select options" do
      agent = build(:agent, agent_type: "mission_designer")

      expect(helper.agent_type_options_for_select(agent).count(["Mission designer", "mission_designer"])).to eq(1)
    end

    it "does not preserve provider names as selectable agent types" do
      agent = build(:agent, agent_type: "openai")

      expect(helper.agent_type_options_for_select(agent)).not_to include(["Openai", "openai"])
    end
  end

  describe "#agent_model_routing_label" do
    it "renders labels for each routing strategy" do
      fallback_agent = build(:agent)
      allow(fallback_agent).to receive(:model_routing_config).and_return(
        "strategy" => "fallback",
        "fallback_models" => [{ "model_id" => "a" }, { "model_id" => "b" }],
      )

      expect(helper.agent_model_routing_label(fallback_agent)).to eq("Fallback (2 alternate models)")
      expect(helper.agent_model_routing_label("strategy" => "canary", "canary_percent" => 15)).to eq("Canary (15%)")
      expect(helper.agent_model_routing_label("strategy" => "ab_test")).to eq("A/B Compare")
      expect(helper.agent_model_routing_label("strategy" => "single")).to eq("Single Model")
      expect(helper.agent_model_routing_label("strategy" => "canary")).to eq("Canary (?%)")
    end

    it "renders fallback without an alternate count when no fallback models are configured" do
      expect(helper.agent_model_routing_label("strategy" => "fallback", "fallback_models" => [])).to eq("Fallback")
    end
  end

  describe "#agent_subagent_count_label" do
    it "returns singular for one sub-agent" do
      agent = create(:agent)
      subagent = create(:agent)
      agent.update!(subagent_ids: [subagent.id])

      expect(helper.agent_subagent_count_label(agent)).to eq("1 sub-agent")
    end

    it "returns plural for multiple sub-agents" do
      agent = create(:agent)
      sub1 = create(:agent)
      sub2 = create(:agent)
      agent.update!(subagent_ids: [sub1.id, sub2.id])

      expect(helper.agent_subagent_count_label(agent)).to eq("2 sub-agents")
    end

    it "returns zero sub-agents when none exist" do
      agent = create(:agent)
      expect(helper.agent_subagent_count_label(agent)).to eq("0 sub-agents")
    end
  end

  describe "#agent_skill_catalog_count_label" do
    it "returns singular for one skill catalog" do
      agent = build(:agent)
      agent.skill_catalog_ids = [1]

      expect(helper.agent_skill_catalog_count_label(agent)).to eq("1 skill catalog")
    end

    it "returns plural for multiple skill catalogs" do
      agent = build(:agent)
      agent.skill_catalog_ids = [1, 2]

      expect(helper.agent_skill_catalog_count_label(agent)).to eq("2 skill catalogs")
    end
  end

  describe "#agent_skill_count_label" do
    it "uses an explicit count when provided" do
      expect(helper.agent_skill_count_label(build(:agent), 1)).to eq("1 skill")
    end
  end

  describe "#agent_temperature_label" do
    it "returns 'Precise' for low temperatures" do
      expect(helper.agent_temperature_label(0.1)).to eq("Precise")
    end

    it "returns 'Balanced' for medium temperatures" do
      expect(helper.agent_temperature_label(0.5)).to eq("Balanced")
    end

    it "returns 'Creative' for higher temperatures" do
      expect(helper.agent_temperature_label(1.0)).to eq("Creative")
    end

    it "returns 'Experimental' for very high temperatures" do
      expect(helper.agent_temperature_label(1.5)).to eq("Experimental")
    end
  end

  describe "#agent_temperature_color" do
    it "returns blue for precise range" do
      expect(helper.agent_temperature_color(0.2)).to eq("text-blue-500")
    end

    it "returns green for balanced range" do
      expect(helper.agent_temperature_color(0.5)).to eq("text-green-500")
    end

    it "returns amber for creative range" do
      expect(helper.agent_temperature_color(1.0)).to eq("text-amber-500")
    end

    it "returns red for experimental range" do
      expect(helper.agent_temperature_color(1.5)).to eq("text-red-500")
    end
  end

  describe "#agent_model_display" do
    it "returns the model_id when present" do
      expect(helper.agent_model_display("gpt-4.1")).to eq("gpt-4.1")
    end

    it "returns fallback text when blank" do
      expect(helper.agent_model_display("")).to eq("Not configured")
    end

    it "returns the system-preference fallback for system-preference agents" do
      agent = build(:agent, model_id: nil, llm_connector: nil, llm_config_source: "system_preference")
      allow(agent).to receive(:resolved_model_id).and_return(nil)

      expect(helper.agent_model_display(agent)).to eq("System preference")
    end

    it "returns the runtime fallback for runtime-configured agents" do
      agent = build(:agent, model_id: nil, llm_connector: nil, llm_config_source: "runtime")
      allow(agent).to receive(:resolved_model_id).and_return(nil)

      expect(helper.agent_model_display(agent)).to eq("Runtime supplied")
    end
  end

  describe "#agent_llm_source_label" do
    it "returns the system-preference label" do
      agent = build(:agent, llm_config_source: "system_preference")

      expect(helper.agent_llm_source_label(agent)).to eq("System Preference")
    end

    it "returns the runtime label" do
      agent = build(:agent, llm_config_source: "runtime")

      expect(helper.agent_llm_source_label(agent)).to eq("Runtime Supplied")
    end
  end

  describe "#agent_llm_connector_display" do
    it "returns fallback text when no connector is configured" do
      agent = build(:agent)
      allow(agent).to receive(:resolved_llm_connector).and_return(nil)

      expect(helper.agent_llm_connector_display(agent)).to eq("Not configured")
    end

    it "falls back to 'LLM' when the resolved connector has no provider_label" do
      agent = build(:agent)
      connector = double("Connector", name: "My Connector") # rubocop:disable RSpec/VerifiedDoubles
      allow(agent).to receive(:resolved_llm_connector).and_return(connector)

      expect(helper.agent_llm_connector_display(agent)).to eq("My Connector (LLM)")
    end
  end

  describe "#agent_input_count_label" do
    it "returns the pluralized input count" do
      agent = build(:agent)
      agent.input_schema = [
        { variable_name: "name", label: "Name", field_type: "string" },
        { variable_name: "age", label: "Age", field_type: "number" },
      ]

      expect(helper.agent_input_count_label(agent)).to eq("2 inputs")
    end
  end

  describe "#models_for_select" do
    it "returns options array with provider and capability metadata" do
      model_struct = Struct.new(:model_id, :name, :provider, :supports_temperature?, :supports_reasoning?)
      models = [model_struct.new("gpt-4.1", "GPT-4.1", "openai", true, true)]
      result = helper.models_for_select(models)

      expected = [[
        "GPT-4.1",
        "gpt-4.1",
        {
          data: {
            custom_properties: {
              provider: "openai",
              supports_temperature: true,
              supports_reasoning: true,
            }.to_json,
          },
        },
      ]]

      expect(result).to eq(expected)
    end
  end

  describe "#llm_connectors_for_select" do
    it "uses provider_label when connector responds to it" do
      connector = double("Connector", id: 1, name: "My LLM", provider_label: "OpenAI") # rubocop:disable RSpec/VerifiedDoubles
      connectors = [connector]
      result = helper.llm_connectors_for_select(connectors)
      expect(result).to eq([["My LLM (OpenAI)", 1]])
    end

    it "falls back to 'LLM' when connector does not respond to provider_label" do
      connector = double("Connector", id: 2, name: "My MCP") # rubocop:disable RSpec/VerifiedDoubles
      connectors = [connector]
      result = helper.llm_connectors_for_select(connectors)
      expect(result).to eq([["My MCP (LLM)", 2]])
    end
  end

  describe "#capability_summary" do
    it "returns summary for TitleGenerator with inherit config" do
      agent = create(:agent)
      agent.set_capability_config("chat_title_generator", {
                                    "max_length" => 30,
                                    "max_turns" => 3,
                                    "llm_config_source" => "inherit",
                                  }, enabled: true,)
      agent.save!
      cap = agent.configured_capabilities.first
      expect(helper.capability_summary(cap)).to eq("max 30 chars · 3 turns · inherit LLM")
    end

    it "returns summary for TitleGenerator with custom config" do
      agent = create(:agent)
      agent.set_capability_config("chat_title_generator", {
                                    "max_length" => 50,
                                    "max_turns" => 5,
                                    "llm_config_source" => "custom",
                                    "model_id" => "gpt-4.1-mini",
                                  }, enabled: true,)
      agent.save!
      cap = agent.configured_capabilities.first
      expect(helper.capability_summary(cap)).to eq("max 50 chars · 5 turns · custom LLM")
    end

    it "returns Enabled for unknown capability types" do
      cap = double(configurator: double)
      expect(helper.capability_summary(cap)).to eq("Enabled")
    end
  end
end
