# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::LlmNodeRuntimeConfig do
  let(:mission) { create(:mission) }
  let(:tenant) { mission.operation.tenant }
  let(:run) { create(:mission_run, mission:) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:connector) { create(:connector, :llm_provider, :enabled, tenant:) }
  let(:runtime_connector) { create(:connector, :llm_provider, :enabled, tenant:) }

  before do
    create(:model, model_id: "gpt-node", provider: "openai", capabilities: ["temperature", "reasoning"])
    create(:model, model_id: "gpt-system", provider: "openai", capabilities: ["temperature", "reasoning"])
    create(:model, model_id: "gpt-runtime", provider: "openai", capabilities: ["temperature", "reasoning"])
  end

  def resolve_config(node_data)
    described_class.resolve(context:, node_data:)
  end

  def create_default_preference(**attributes)
    create(:system_preference, { tenant:, llm_connector: connector, model_id: "gpt-system" }.merge(attributes))
  end

  def set_runtime_config(**attributes)
    context.set_variable("_llm_config", attributes.deep_stringify_keys)
  end

  def expect_resolved(resolved, **attributes)
    expect(resolved).to have_attributes(attributes)
  end

  describe ".source_for" do
    it "defaults omitted connection settings to system preference" do
      expect(described_class.source_for({ "prompt" => "Hello" })).to eq("system_preference")
    end

    it "keeps legacy direct connector/model data on node configuration" do
      expect(described_class.source_for({ "connector_id" => "1", "model" => "gpt-node" })).to eq("node")
    end
  end

  describe ".resolve" do
    it "resolves node-owned connector, model, and thinking settings" do
      resolved, error = resolve_config(
        "llm_config_source" => "node",
        "connector_id" => connector.id.to_s,
        "model" => "gpt-node",
        "temperature" => "0.2",
        "thinking_effort" => "low",
        "thinking_budget" => "128",
        "custom_llm_params" => { "top_p" => 0.7 },
        "model_routing_config" => { "strategy" => "fallback",
                                    "fallback_models" => [{ "connector_id" => runtime_connector.id,
                                                            "model_id" => "gpt-runtime", }], },
      )

      expect(error).to be_nil
      expect_resolved(resolved, source: "node", connector:, model_id: "gpt-node", temperature: "0.2",
                                thinking_effort: "low", thinking_budget: "128", custom_params: { "top_p" => 0.7 },
                                model_routing_config: {
                                  "strategy" => "fallback",
                                  "fallback_models" => [{ "connector_id" => runtime_connector.id,
                                                          "model_id" => "gpt-runtime", }],
                                },)
    end

    it "resolves system preference connector, model, and thinking settings" do
      create_default_preference(temperature: 0.3, thinking_effort: "high", thinking_budget: 1024,
                                custom_llm_params: { "top_p" => 0.9 },
                                model_routing_config: {
                                  "strategy" => "ab_test",
                                  "comparison_model" => { "connector_id" => runtime_connector.id,
                                                          "model_id" => "gpt-runtime", },
                                },)

      resolved, error = resolve_config("llm_config_source" => "system_preference")

      expect(error).to be_nil
      expect_resolved(resolved, source: "system_preference", connector:, model_id: "gpt-system", temperature: 0.3,
                                thinking_effort: "high", thinking_budget: 1024, custom_params: { "top_p" => 0.9 },
                                model_routing_config: {
                                  "strategy" => "ab_test",
                                  "comparison_model" => { "connector_id" => runtime_connector.id,
                                                          "model_id" => "gpt-runtime", },
                                },)
    end

    it "rejects an invalid LLM source" do
      resolved, error = resolve_config("llm_config_source" => "workspace")

      expect(resolved).to be_nil
      expect(error).to eq("LLM source is invalid")
    end

    it "requires configured system preferences for system preference source" do
      resolved, error = resolve_config("llm_config_source" => "system_preference")

      expect(resolved).to be_nil
      expect(error).to eq("LLM connector not configured")
    end

    it "uses runtime-supplied connector, model, and thinking settings over system preference" do
      create_default_preference(temperature: 0.3, thinking_effort: "low", thinking_budget: 256,
                                custom_llm_params: { "top_p" => 0.5 },)
      set_runtime_config(connector_id: runtime_connector.id.to_s, model: "gpt-runtime", temperature: 1.1,
                         thinking_effort: "high", thinking_budget: 2048,
                         custom_llm_params: { "top_p" => 0.95 },
                         model_routing_config: {
                           "strategy" => "canary",
                           "canary_model" => { "connector_id" => connector.id, "model_id" => "gpt-node" },
                           "canary_percent" => 15,
                         },)

      resolved, error = resolve_config("llm_config_source" => "runtime")

      expect(error).to be_nil
      expect_resolved(resolved, source: "runtime", connector: runtime_connector, model_id: "gpt-runtime",
                                temperature: 1.1, thinking_effort: "high", thinking_budget: 2048,
                                custom_params: { "top_p" => 0.95 },
                                model_routing_config: {
                                  "strategy" => "canary",
                                  "canary_model" => { "connector_id" => connector.id, "model_id" => "gpt-node" },
                                  "canary_percent" => 15,
                                },)
    end

    it "falls back to system preference when runtime config is absent" do
      create_default_preference(temperature: 0.4, thinking_effort: "medium", thinking_budget: 768)

      resolved, error = resolve_config("llm_config_source" => "runtime")

      expect(error).to be_nil
      expect_resolved(resolved, connector:, model_id: "gpt-system", temperature: 0.4,
                                thinking_effort: "medium", thinking_budget: 768,)
    end

    it "merges partial runtime config over system preference" do
      create_default_preference(thinking_effort: "low", thinking_budget: 256)
      set_runtime_config(thinking_effort: "high")

      resolved, error = resolve_config("llm_config_source" => "runtime")

      expect(error).to be_nil
      expect_resolved(resolved, connector:, model_id: "gpt-system", thinking_effort: "high", thinking_budget: 256)
    end

    it "reads runtime config from trigger data when no runtime variable is set" do
      create_default_preference
      context.set_variable("_trigger_data", { "llm_config" => { "model_id" => "gpt-runtime" } })

      resolved, error = resolve_config("llm_config_source" => "runtime")

      expect(error).to be_nil
      expect_resolved(resolved, connector:, model_id: "gpt-runtime")
    end

    it "accepts runtime config as a JSON string" do
      create_default_preference
      context.set_variable("_llm_config", { model_id: "gpt-runtime" }.to_json)

      resolved, error = resolve_config("llm_config_source" => "runtime")

      expect(error).to be_nil
      expect_resolved(resolved, connector:, model_id: "gpt-runtime")
    end

    it "falls back to system preference when runtime config is malformed" do
      create_default_preference
      context.set_variable("_llm_config", "{")

      resolved, error = resolve_config("llm_config_source" => "runtime")

      expect(error).to be_nil
      expect_resolved(resolved, connector:, model_id: "gpt-system")
    end

    it "falls back to system preference when runtime config is not hash-like" do
      create_default_preference
      context.set_variable("_llm_config", 123)

      resolved, error = resolve_config("llm_config_source" => "runtime")

      expect(error).to be_nil
      expect_resolved(resolved, connector:, model_id: "gpt-system")
    end

    it "rejects a runtime connector from another tenant" do
      tenant
      foreign_connector = create(:connector, :llm_provider, :enabled, tenant: create(:tenant))
      context.set_variable("_llm_config", { "connector_id" => foreign_connector.id.to_s, "model" => "gpt-runtime" })

      resolved, error = resolve_config("llm_config_source" => "runtime")

      expect(resolved).to be_nil
      expect(error).to eq("LLM connector not configured")
    end

    it "requires tenant context before resolving a connector" do
      tenantless_context = Missions::ExecutionContext.new(mission_run: nil)

      resolved, error = described_class.resolve(
        context: tenantless_context,
        node_data: { "llm_config_source" => "node", "connector_id" => connector.id.to_s, "model" => "gpt-node" },
      )

      expect(resolved).to be_nil
      expect(error).to eq("LLM connector not configured")
    end

    it "requires tenant context before resolving system preferences" do
      tenantless_context = Missions::ExecutionContext.new(mission_run: nil)

      resolved, error = described_class.resolve(
        context: tenantless_context,
        node_data: { "llm_config_source" => "system_preference" },
      )

      expect(resolved).to be_nil
      expect(error).to eq("LLM connector not configured")
    end
  end
end
