# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations

require "rails_helper"

RSpec.describe Agents::PromptPreview do
  describe "#call" do
    let(:tenant) { create(:tenant) }
    let(:operation) { create(:operation, tenant:) }
    let(:connector) { create(:connector, :llm_provider, :enabled, tenant:) }
    let(:model) { create(:model, model_id: "gpt-preview", provider: connector.provider) }
    let(:user) { create(:user, tenant:) }

    it "builds a deterministic preview without creating a chat" do
      BuiltinTools::Registrations.register_all!
      model
      preference = SystemPreference.current(tenant:)
      preference.update!(
        llm_connector: connector,
        model_id: model.model_id,
        temperature: 0.2,
        thinking_effort: "low",
        thinking_budget: 64,
        custom_llm_params: { "top_p" => 0.9 },
        model_routing_config: { "strategy" => "single" },
      )
      agent = configured_system_preference_agent

      allow(agent).to receive_messages(
        skill_system_prompt_addition: "Skill prompt",
        capability_system_prompt_additions: ["Capability prompt"],
      )

      preview = nil
      expect do
        preview = described_class.new(agent, user:).call
      end.not_to change(Chat, :count)

      expect(preview[:digest]).to match(/\A[0-9a-f]{64}\z/)
      expect(preview.dig(:model, :connector)).to eq(connector.name)
      expect(preview.dig(:model, :temperature)).to eq(0.2)
      expect(preview.dig(:model, :thinking_effort)).to eq("low")
      expect(preview.dig(:model, :custom_params)).to eq({ "top_p" => 0.9 })
      expect(preview.dig(:response_format, :schema)).to eq({ "type" => "object" })
      expect(preview[:instructions]).to include("Sample String")
      expect(preview[:tools].first[:name]).to eq("SQL Tool")
      expect(preview[:builtin_tools].pluck(:available)).to eq([true, false])
      expect(preview[:subagents].first[:name]).to eq("Helper Agent")
      expect(preview[:skill_catalogs].first[:skills]).to eq(1)
      expect(preview[:capabilities].first[:key]).to eq("chat_title_generator")
      expect(preview[:prompt_additions].pluck(:content)).to eq(["Skill prompt", "Capability prompt"])
    end

    it "uses direct agent settings and placeholder labels when no system preference is active" do
      agent = build(
        :agent,
        operation:,
        llm_connector: nil,
        model_id: nil,
        llm_config_source: "agent",
        instructions: "Hello {{missing_label}}",
      )
      agent.input_schema = [
        { "variable_name" => "missing_label", "field_type" => "string" },
        { "variable_name" => "", "label" => "Ignored", "field_type" => "string" },
      ]

      preview = described_class.new(agent, user:).call

      expect(preview.dig(:model, :source)).to eq("agent")
      expect(preview.dig(:model, :connector)).to be_nil
      expect(preview.dig(:model, :provider)).to be_nil
      expect(preview.dig(:model, :temperature)).to eq(agent.temperature)
      expect(preview[:inputs].first[:sample]).to eq("Sample Missing label")
      expect(preview[:prompt_additions]).to eq([])
    end

    def configured_system_preference_agent
      agent = create(
        :agent,
        operation:,
        llm_connector: nil,
        model_id: nil,
        llm_config_source: "system_preference",
        instructions: "Answer for {{string_field}}",
      )
      agent.response_format = "json_schema"
      agent.response_schema = { "type" => "object" }
      agent.input_schema = preview_input_schema
      agent.runtime_tool_keys = ["resources.list_resources", "missing.tool"]
      agent.tool_ids = [create(:tool, :sql_query, :enabled, operation:, name: "SQL Tool").id]
      agent.subagent_ids = [create(:agent, :enabled, operation:, name: "Helper Agent").id]
      agent.skill_catalog_ids = [skill_catalog_with_skill.id]
      agent.set_capability_config("chat_title_generator", { "max_length" => 30 }, enabled: true)
      agent.save!
      agent
    end

    def preview_input_schema
      AgentConfigurationValidations::INPUT_FIELD_TYPES.map do |field_type|
        {
          "variable_name" => "#{field_type}_field",
          "label" => field_type.humanize,
          "field_type" => field_type,
          "required" => field_type == "string",
          "config" => {},
        }
      end
    end

    def skill_catalog_with_skill
      @skill_catalog_with_skill ||= begin
        catalog = create(:skill_catalog, operation:)
        create(:skill, skill_catalog: catalog)
        catalog
      end
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
