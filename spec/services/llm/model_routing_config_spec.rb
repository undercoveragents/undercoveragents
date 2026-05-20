# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::ModelRoutingConfig do
  describe ".normalize" do
    it "returns the default strategy for blank input" do
      expect(described_class.normalize(nil)).to eq({ "strategy" => "single" })
      expect(described_class.normalize("  ")).to eq({ "strategy" => "single" })
    end

    it "normalizes routing json strings" do
      normalized = described_class.normalize(
        {
          strategy: "fallback",
          fallback_models: [{ connector_id: "12", model_id: :gpt_4_1_mini }],
        }.to_json,
      )

      expect(normalized).to eq(
        "strategy" => "fallback",
        "fallback_models" => [{ "connector_id" => 12, "model_id" => "gpt_4_1_mini" }],
      )
    end

    it "raises when the payload is not an object" do
      expect do
        described_class.normalize('["bad"]')
      end.to raise_error(described_class::InvalidConfigError, /JSON object/)
    end

    it "supports hash-like inputs that implement to_h" do
      hash_like = Class.new do
        def initialize(payload)
          @payload = payload
        end

        def to_h
          @payload
        end
      end.new(
        { strategy: "ab_test", comparison_model: { connector_id: "9", model_id: :gpt } },
      )

      normalized = described_class.normalize(
        hash_like,
      )

      expect(normalized).to eq(
        "strategy" => "ab_test",
        "comparison_model" => { "connector_id" => 9, "model_id" => "gpt" },
      )
    end

    it "falls back to the default strategy for non-hash-like values" do
      expect(described_class.normalize(123)).to eq({ "strategy" => "single" })
    end

    it "preserves partial routes when connector_id or model_id is missing" do
      normalized = described_class.normalize(
        {
          strategy: "fallback",
          fallback_models: [{ model_id: :gpt_only }, { connector_id: "12" }],
        },
      )

      expect(normalized).to eq(
        "strategy" => "fallback",
        "fallback_models" => [{ "model_id" => "gpt_only" }, { "connector_id" => 12 }],
      )
    end

    it "rejects route values that are not objects" do
      expect do
        described_class.normalize({ strategy: "canary", canary_model: "bad-route" })
      end.to raise_error(described_class::InvalidConfigError, /Model route must be an object/)
    end
  end

  describe ".persistable" do
    it "returns an empty hash for the default strategy" do
      expect(described_class.persistable(nil)).to eq({})
      expect(described_class.persistable({ "strategy" => "single" })).to eq({})
    end
  end

  describe ".validate!" do
    it "requires at least one fallback model" do
      expect do
        described_class.validate!({ "strategy" => "fallback" })
      end.to raise_error(described_class::InvalidConfigError, /fallback_models/)
    end

    it "requires a valid canary percent" do
      expect do
        described_class.validate!(
          {
            "strategy" => "canary",
            "canary_model" => { "connector_id" => 1, "model_id" => "gpt-5-mini" },
            "canary_percent" => 0,
          },
        )
      end.to raise_error(described_class::InvalidConfigError, /canary_percent/)
    end

    it "rejects non-integer canary percentages" do
      expect do
        described_class.normalize(
          {
            "strategy" => "canary",
            "canary_model" => { "connector_id" => 1, "model_id" => "gpt-5-mini" },
            "canary_percent" => "abc",
          },
        )
      end.to raise_error(described_class::InvalidConfigError, /Canary percent must be an integer/)
    end

    it "requires a comparison model for ab tests" do
      expect do
        described_class.validate!({ "strategy" => "ab_test" })
      end.to raise_error(described_class::InvalidConfigError, /comparison_model/)
    end

    it "rejects unknown strategies" do
      expect do
        described_class.validate!({ "strategy" => "mystery" })
      end.to raise_error(described_class::InvalidConfigError, /strategy is not included in the list/)
    end

    it "requires a complete canary route" do
      expect do
        described_class.validate!(
          {
            "strategy" => "canary",
            "canary_model" => { "connector_id" => 1 },
            "canary_percent" => 10,
          },
        )
      end.to raise_error(described_class::InvalidConfigError, /canary_model must include connector_id and model_id/)
    end

    it "accepts a valid canary configuration" do
      tenant = create(:tenant)
      connector = create(:connector, :llm_provider, :enabled, tenant:)

      expect(
        described_class.validate!(
          {
            "strategy" => "canary",
            "canary_model" => { "connector_id" => connector.id, "model_id" => "gpt-4.1-mini" },
            "canary_percent" => 10,
          },
          tenant:,
        ),
      ).to include("strategy" => "canary")
    end

    it "validates connector tenant and type" do
      tenant = create(:tenant)
      sql_connector = create(:connector, :sql_database, tenant:)

      expect do
        described_class.validate!(
          {
            "strategy" => "ab_test",
            "comparison_model" => { "connector_id" => sql_connector.id, "model_id" => "gpt-4.1" },
          },
          tenant:,
        )
      end.to raise_error(described_class::InvalidConfigError,
                         /comparison model connector must be an LLM Provider connector/,)
    end

    it "flags missing route connectors" do
      tenant = create(:tenant)

      expect do
        described_class.validate!(
          {
            "strategy" => "ab_test",
            "comparison_model" => { "connector_id" => 999_999, "model_id" => "gpt-4.1" },
          },
          tenant:,
        )
      end.to raise_error(described_class::InvalidConfigError, /comparison model connector is invalid/)
    end

    it "ignores blank route entries and blank connector ids during connector validation" do
      tenant = create(:tenant)
      connector = create(:connector, :llm_provider, :enabled, tenant:)

      expect(
        described_class.validate!(
          {
            "strategy" => "fallback",
            "fallback_models" => [
              nil,
              { "connector_id" => "", "model_id" => "ignored" },
              { "connector_id" => connector.id, "model_id" => "gpt-4.1-mini" },
            ],
          },
          tenant:,
        ),
      ).to include("strategy" => "fallback")
    end

    it "flags blank model ids after connector lookup succeeds" do
      tenant = create(:tenant)
      connector = create(:connector, :llm_provider, :enabled, tenant:)

      expect do
        described_class.validate!(
          {
            "strategy" => "fallback",
            "fallback_models" => [{ "connector_id" => connector.id }],
          },
          tenant:,
        )
      end.to raise_error(described_class::InvalidConfigError, /fallback model #1 model_id can't be blank/)
    end

    it "returns the normalized config when valid" do
      tenant = create(:tenant)
      connector = create(:connector, :llm_provider, :enabled, tenant:)

      config = described_class.validate!(
        {
          "strategy" => "ab_test",
          "comparison_model" => { "connector_id" => connector.id.to_s, "model_id" => "gpt-4.1" },
        },
        tenant:,
      )

      expect(config).to eq(
        "strategy" => "ab_test",
        "comparison_model" => { "connector_id" => connector.id, "model_id" => "gpt-4.1" },
      )
    end

    it "includes canary routes in the validation route list" do
      routes = described_class.send(
        :routes_for_validation,
        { "canary_model" => { "connector_id" => 1, "model_id" => "gpt-4.1-mini" } },
      )

      expect(routes).to eq([["canary model", { "connector_id" => 1, "model_id" => "gpt-4.1-mini" }]])
    end

    it "skips blank routes during connector validation" do
      errors = []

      described_class.send(:validate_route_connectors, { "fallback_models" => [nil] }, tenant: create(:tenant), errors:)

      expect(errors).to be_empty
    end
  end
end
