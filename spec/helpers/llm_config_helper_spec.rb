# frozen_string_literal: true

require "rails_helper"

RSpec.describe LlmConfigHelper do
  describe "#model_routing_strategy_options_for_select" do
    it "returns the supported routing strategies in display order" do
      expect(helper.model_routing_strategy_options_for_select).to eq(
        [
          ["Single Model", "single"],
          ["Fallback", "fallback"],
          ["Canary", "canary"],
          ["A/B Compare", "ab_test"],
        ],
      )
    end
  end

  describe "#model_routing_editor_config" do
    it "normalizes valid routing config input" do
      connector = create(:connector, :llm_provider, :enabled)

      expect(
        helper.model_routing_editor_config(
          {
            "strategy" => "fallback",
            "fallback_models" => [{ "connector_id" => connector.id.to_s, "model_id" => "gpt-4.1-mini" }],
          },
        ),
      ).to eq(
        "strategy" => "fallback",
        "fallback_models" => [{ "connector_id" => connector.id, "model_id" => "gpt-4.1-mini" }],
      )
    end

    it "falls back to the default strategy for invalid editor values" do
      expect(helper.model_routing_editor_config('{"strategy":"fallback"')).to eq(
        Llm::ModelRoutingConfig.default,
      )
    end
  end

  describe "#model_routing_connector_options" do
    it "formats connector labels for the routing editor" do
      connector = create(:connector, :llm_provider, :enabled, name: "Primary OpenAI")

      expect(helper.model_routing_connector_options([connector])).to eq(
        [{ value: connector.id.to_s, label: "#{connector.name} (#{connector.provider_label})" }],
      )
    end
  end

  describe "#model_routing_model_catalog" do
    it "groups available models by connector provider" do
      openai_connector = create(:connector, :llm_provider, :enabled)
      anthropic_connector = create(:connector, :llm_provider, :enabled, provider: "anthropic", name: "Anthropic")
      openai_model = create(:model, provider: openai_connector.provider, model_id: "gpt-4.1", name: "GPT 4.1")
      anthropic_model = create(
        :model,
        provider: anthropic_connector.provider,
        model_id: "claude-sonnet-4.5",
        name: "Claude Sonnet 4.5",
      )

      expect(helper.model_routing_model_catalog([openai_connector, anthropic_connector])).to eq(
        openai_connector.id.to_s => [{ value: openai_model.model_id, label: openai_model.name }],
        anthropic_connector.id.to_s => [{ value: anthropic_model.model_id, label: anthropic_model.name }],
      )
    end

    it "returns an empty catalog when no connectors are available" do
      expect(helper.model_routing_model_catalog([])).to eq({})
    end
  end

  describe "#model_routing_editor_state" do
    it "builds the editor state for compact canary configuration" do
      connector = create(:connector, :llm_provider, :enabled)
      create(:model, provider: connector.provider, model_id: "gpt-4.1-mini", name: "GPT 4.1 Mini")

      state = helper.model_routing_editor_state(
        input_value: {
          "strategy" => "canary",
          "canary_model" => { "connector_id" => connector.id, "model_id" => "gpt-4.1-mini" },
          "canary_percent" => 15,
        },
        connectors: [connector],
        compact: true,
      )

      expect(state).to include(
        strategy: "canary",
        canary_route: { "connector_id" => connector.id, "model_id" => "gpt-4.1-mini" },
        canary_percent: 15,
        select_class: "ms-prop-select",
        input_class: "ms-prop-input",
        container_classes: "llm-routing-editor llm-routing-editor--compact",
      )
    end

    it "seeds a blank fallback row when fallback is selected without saved routes" do
      state = helper.model_routing_editor_state(
        input_value: { "strategy" => "fallback" },
        connectors: [],
        compact: false,
      )

      expect(state[:fallback_routes]).to eq([{}])
      expect(state[:container_classes]).to eq("llm-routing-editor")
    end
  end

  describe "#model_routing_route_state" do
    it "builds the route state for the selected connector" do
      route_state = helper.model_routing_route_state(
        route: { "connector_id" => 12, "model_id" => "gpt-4.1-mini" },
        model_catalog: { "12" => [{ value: "gpt-4.1-mini", label: "GPT 4.1 Mini" }] },
        options: {
          label_prefix: "Canary",
          select_class: "ms-prop-select",
          wrapper_class: "llm-routing-editor__route",
          removable: true,
        },
      )

      expect(route_state).to eq(
        connector_id: "12",
        model_id: "gpt-4.1-mini",
        model_options: [{ value: "gpt-4.1-mini", label: "GPT 4.1 Mini" }],
        label_prefix: "Canary",
        select_class: "ms-prop-select",
        wrapper_class: "llm-routing-editor__route",
        removable: true,
      )
    end
  end
end
