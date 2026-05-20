# frozen_string_literal: true

# == Schema Information
#
# Table name: system_preferences
# Database name: primary
#
#  id                     :bigint           not null, primary key
#  custom_llm_params      :jsonb            not null
#  model_routing_config   :jsonb            not null
#  temperature            :float
#  thinking_budget        :integer
#  thinking_effort        :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  embedding_connector_id :bigint
#  embedding_model_id     :string
#  image_connector_id     :bigint
#  image_model_id         :string
#  llm_connector_id       :bigint
#  model_id               :string
#  tenant_id              :bigint           not null
#
# Indexes
#
#  index_system_preferences_on_tenant_id  (tenant_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (embedding_connector_id => connectors.id)
#  fk_rails_...  (image_connector_id => connectors.id)
#  fk_rails_...  (llm_connector_id => connectors.id)
#  fk_rails_...  (tenant_id => tenants.id)
#
require "rails_helper"

RSpec.describe SystemPreference do
  describe "validations" do
    it "is valid without any configuration" do
      pref = described_class.new
      expect(pref).to be_valid
    end

    it "is valid with both connector and model" do
      connector = create(:connector, :llm_provider, :enabled)
      pref = described_class.new(llm_connector: connector, model_id: "gpt-4.1")
      expect(pref).to be_valid
    end

    it "is invalid with connector but no model" do
      connector = create(:connector, :llm_provider, :enabled)
      pref = described_class.new(llm_connector: connector, model_id: nil)
      expect(pref).not_to be_valid
      expect(pref.errors[:model_id]).to be_present
    end

    it "is invalid with a non-LLM-provider connector" do
      connector = create(:connector, :sql_database)
      pref = described_class.new(llm_connector: connector, model_id: "gpt-4.1")
      expect(pref).not_to be_valid
      expect(pref.errors[:llm_connector_id]).to be_present
    end

    it "rejects connector with missing type" do
      connector = create(:connector, :sql_database)
      pref = described_class.new(llm_connector: connector, model_id: "gpt-4.1")
      expect(pref).not_to be_valid
      expect(pref.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
    end

    it "is invalid when llm_connector_id points to a missing connector" do
      pref = described_class.new(llm_connector_id: 999_999, model_id: "gpt-4.1")

      expect(pref).not_to be_valid
      expect(pref.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
    end

    context "with embedding fields" do
      it "is valid with both embedding connector and model" do
        connector = create(:connector, :llm_provider, :enabled)
        pref = described_class.new(embedding_connector: connector, embedding_model_id: "text-embedding-3-small")
        expect(pref).to be_valid
      end

      it "is invalid with embedding connector but no model" do
        connector = create(:connector, :llm_provider, :enabled)
        pref = described_class.new(embedding_connector: connector, embedding_model_id: nil)
        expect(pref).not_to be_valid
        expect(pref.errors[:embedding_model_id]).to be_present
      end

      it "is invalid with a non-LLM-provider embedding connector" do
        connector = create(:connector, :sql_database)
        pref = described_class.new(embedding_connector: connector, embedding_model_id: "text-embedding-3-small")
        expect(pref).not_to be_valid
        expect(pref.errors[:embedding_connector_id]).to include("must be an LLM Provider connector")
      end

      it "is invalid when embedding_connector_id points to a missing connector" do
        pref = described_class.new(embedding_connector_id: 999_999, embedding_model_id: "text-embedding-3-small")

        expect(pref).not_to be_valid
        expect(pref.errors[:embedding_connector_id]).to include("must be an LLM Provider connector")
      end
    end

    context "with image fields" do
      it "is valid with both image connector and model" do
        connector = create(:connector, :llm_provider, :enabled)
        pref = described_class.new(image_connector: connector, image_model_id: "gpt-image-1")
        expect(pref).to be_valid
      end

      it "is invalid with image connector but no model" do
        connector = create(:connector, :llm_provider, :enabled)
        pref = described_class.new(image_connector: connector, image_model_id: nil)
        expect(pref).not_to be_valid
        expect(pref.errors[:image_model_id]).to be_present
      end

      it "is invalid with a non-LLM-provider image connector" do
        connector = create(:connector, :sql_database)
        pref = described_class.new(image_connector: connector, image_model_id: "gpt-image-1")
        expect(pref).not_to be_valid
        expect(pref.errors[:image_connector_id]).to include("must be an LLM Provider connector")
      end

      it "is invalid when image_connector_id points to a missing connector" do
        pref = described_class.new(image_connector_id: 999_999, image_model_id: "gpt-image-1")

        expect(pref).not_to be_valid
        expect(pref.errors[:image_connector_id]).to include("must be an LLM Provider connector")
      end
    end

    it "rejects connectors from another tenant" do
      tenant = create(:tenant)
      other_connector = create(:connector, :llm_provider, :enabled, tenant: create(:tenant))
      pref = described_class.new(tenant:, llm_connector: other_connector, model_id: "gpt-4.1")

      expect(pref).not_to be_valid
      expect(pref.errors[:llm_connector]).to include("must belong to the same tenant")
    end

    it "rejects temperature outside the supported range" do
      pref = described_class.new(temperature: 2.1)

      expect(pref).not_to be_valid
      expect(pref.errors[:temperature]).to include("must be between 0.0 and 2.0")
    end

    it "rejects invalid thinking effort" do
      pref = described_class.new(thinking_effort: "maximum")

      expect(pref).not_to be_valid
      expect(pref.errors[:thinking_effort]).to include("is not included in the list")
    end

    it "rejects non-positive thinking budget" do
      pref = described_class.new(thinking_budget: 0)

      expect(pref).not_to be_valid
      expect(pref.errors[:thinking_budget]).to include("must be greater than 0")
    end

    it "rejects invalid custom LLM params JSON" do
      pref = described_class.new(custom_llm_params: "not-json")

      expect(pref).not_to be_valid
      expect(pref.errors[:custom_llm_params].first).to include("must be valid JSON")
    end

    it "rejects invalid model routing config json" do
      pref = described_class.new(model_routing_config: '{"strategy":"canary"')

      expect(pref).not_to be_valid
      expect(pref.errors[:model_routing_config].first).to include("must be valid JSON")
    end

    it "returns the default routing config when stored routing data is malformed" do
      pref = described_class.new
      pref[:model_routing_config] = '["bad"]'

      expect(pref.model_routing_config).to eq(Llm::ModelRoutingConfig.default)
    end

    it "formats non-string routing config JSON inputs for the edit form" do
      pref = described_class.new

      expect(pref.send(:model_routing_config_json_input, nil)).to eq("")
      expect(pref.send(:model_routing_config_json_input, { "strategy" => "fallback" })).to include('"strategy"')
    end

    it "falls back to to_s when formatting routing config JSON fails" do
      pref = described_class.new
      value = Object.new
      value.define_singleton_method(:to_json) { |_state = nil| raise JSON::GeneratorError, "boom" }

      expect(pref.send(:model_routing_config_json_input, value)).to eq(value.to_s)
    end

    it "returns the cached routing JSON input when present" do
      pref = described_class.new

      pref.model_routing_config = '{"strategy":"canary"'

      expect(pref.model_routing_config_json).to eq('{"strategy":"canary"')
    end

    it "formats stored non-default routing config when no cached input is set" do
      pref = described_class.new
      pref[:model_routing_config] = {
        "strategy" => "ab_test",
        "comparison_model" => { "connector_id" => 1, "model_id" => "gpt-4.1" },
      }

      expect(pref.model_routing_config_json).to include('"strategy": "ab_test"')
    end

    it "formats the default routing config as blank input" do
      pref = described_class.new

      expect(pref.send(:formatted_model_routing_config_input, Llm::ModelRoutingConfig.default)).to eq("")
    end
  end

  describe ".current" do
    it "returns the existing record" do
      pref = described_class.create!
      expect(described_class.current).to eq(pref)
    end

    it "creates a new record if none exists" do
      expect { described_class.current }.to change(described_class, :count).by(1)
    end

    it "raises when no tenant can be resolved" do
      allow(Tenant).to receive(:default_tenant).and_return(nil)

      expect { described_class.current(tenant: nil) }.to raise_error("Tenant is required to resolve system preferences")
    end
  end

  describe ".current_settings" do
    it "returns empty hash when no preference exists" do
      expect(described_class.current_settings).to eq({})
    end

    it "returns connector and model settings" do
      pref = create(:system_preference, :configured)
      described_class.invalidate_cache!
      settings = described_class.current_settings
      expect(settings[:llm_connector_id]).to eq(pref.llm_connector_id)
      expect(settings[:model_id]).to eq("gpt-4.1")
    end

    it "returns default LLM option settings" do
      create(:system_preference,
             :configured,
             temperature: 0.3,
             thinking_effort: "high",
             thinking_budget: 1024,
             custom_llm_params: { "top_p" => 0.8 },)
      described_class.invalidate_cache!

      settings = described_class.current_settings

      expect(settings).to include(
        temperature: 0.3,
        thinking_effort: "high",
        thinking_budget: 1024,
        custom_llm_params: { "top_p" => 0.8 },
      )
    end

    it "returns model routing config when configured" do
      connector = create(:connector, :llm_provider, :enabled)
      create(
        :system_preference,
        :configured,
        model_routing_config: {
          "strategy" => "fallback",
          "fallback_models" => [{ "connector_id" => connector.id, "model_id" => "gpt-4.1-mini" }],
        },
      )
      described_class.invalidate_cache!

      expect(described_class.current_settings[:model_routing_config]).to eq(
        "strategy" => "fallback",
        "fallback_models" => [{ "connector_id" => connector.id, "model_id" => "gpt-4.1-mini" }],
      )
    end

    it "returns embedding settings when configured" do
      pref = create(:system_preference, :configured, :with_embedding)
      described_class.invalidate_cache!
      settings = described_class.current_settings
      expect(settings[:embedding_connector_id]).to eq(pref.embedding_connector_id)
      expect(settings[:embedding_model_id]).to eq("text-embedding-3-small")
    end

    it "returns image settings when configured" do
      pref = create(:system_preference, :configured, :with_image)
      described_class.invalidate_cache!
      settings = described_class.current_settings
      expect(settings[:image_connector_id]).to eq(pref.image_connector_id)
      expect(settings[:image_model_id]).to eq("gpt-image-1")
    end

    it "returns an empty hash when tenant is nil" do
      expect(described_class.current_settings(tenant: nil)).to eq({})
    end
  end

  describe ".llm_configured?" do
    it "returns false when not configured" do
      described_class.create!
      described_class.invalidate_cache!
      expect(described_class.llm_configured?).to be false
    end

    it "returns true when configured" do
      create(:system_preference, :configured)
      described_class.invalidate_cache!
      expect(described_class.llm_configured?).to be true
    end
  end

  describe "#configured?" do
    it "returns false without connector" do
      expect(described_class.new).not_to be_configured
    end

    it "returns true with connector and model" do
      pref = create(:system_preference, :configured)
      expect(pref).to be_configured
    end
  end

  describe "#custom_llm_params" do
    it "normalizes JSON strings and exposes pretty JSON" do
      pref = described_class.new(custom_llm_params: '{"top_p":0.9}')

      expect(pref.custom_llm_params).to eq({ "top_p" => 0.9 })
      expect(pref.custom_llm_params_json).to include('"top_p": 0.9')
    end

    it "falls back to empty params for non-object stored values" do
      pref = described_class.new
      pref[:custom_llm_params] = []

      expect(pref.custom_llm_params).to eq({})
    end

    it "serializes stored params when no JSON input is cached" do
      pref = described_class.new
      pref[:custom_llm_params] = { "top_p" => 0.9 }

      expect(pref.custom_llm_params_json).to include('"top_p": 0.9')
    end

    it "returns blank JSON when no custom params are present" do
      expect(described_class.new.custom_llm_params_json).to eq("")
    end

    it "clears custom params from blank input" do
      pref = described_class.new(custom_llm_params: "")

      expect(pref.custom_llm_params).to eq({})
      expect(pref.custom_llm_params_json).to eq("")
    end

    it "preserves invalid non-string input for redisplay" do
      allow(Llm::ChatOptions).to receive(:normalize_custom_params)
        .and_raise(Llm::ChatOptions::InvalidCustomParamsError, "must be a JSON object")
      recursive_value = []
      recursive_value << recursive_value
      pref = described_class.new

      pref.custom_llm_params = nil
      blank_json = pref.custom_llm_params_json
      pref.custom_llm_params = { "top_p" => 0.9 }
      object_json = pref.custom_llm_params_json
      pref.custom_llm_params = recursive_value

      expect(blank_json).to eq("")
      expect(object_json).to include('"top_p": 0.9')
      expect(pref.custom_llm_params_json).to eq("[[...]]")
    end
  end

  describe "#llm_runtime_settings" do
    it "returns connector, model, and default model options together" do
      pref = create(:system_preference,
                    :configured,
                    temperature: 0.4,
                    thinking_effort: "medium",
                    thinking_budget: 512,
                    custom_llm_params: { "top_p" => 0.7 },)

      expect(pref.llm_runtime_settings).to include(
        connector_id: pref.llm_connector_id,
        model_id: "gpt-4.1",
        temperature: 0.4,
        thinking_effort: "medium",
        thinking_budget: 512,
        custom_params: { "top_p" => 0.7 },
      )
      expect(pref.llm_runtime_settings[:context]).to be_present
    end

    it "returns nil for blank optional thinking settings" do
      pref = create(:system_preference, :configured, thinking_effort: "", thinking_budget: nil)

      expect(pref.llm_runtime_settings).to include(thinking_effort: nil, thinking_budget: nil)
    end
  end

  describe "#embedding_configured?" do
    it "returns false without embedding connector" do
      expect(described_class.new).not_to be_embedding_configured
    end

    it "returns true with embedding connector and model" do
      pref = create(:system_preference, :with_embedding)
      expect(pref).to be_embedding_configured
    end
  end

  describe "#image_configured?" do
    it "returns false without image connector" do
      expect(described_class.new).not_to be_image_configured
    end

    it "returns true with image connector and model" do
      pref = create(:system_preference, :with_image)
      expect(pref).to be_image_configured
    end
  end

  describe "#resolve_llm_context" do
    it "returns nil without connector" do
      pref = described_class.new
      expect(pref.resolve_llm_context).to be_nil
    end

    it "returns context from connector" do
      pref = create(:system_preference, :configured)
      expect(pref.resolve_llm_context).to be_present
    end

    it "returns nil when connector has no configurator" do
      connector = create(:connector, :llm_provider, :enabled)
      pref = described_class.new(llm_connector: connector, model_id: "gpt-4.1")
      allow(connector).to receive(:configurator).and_return(nil)
      expect(pref.resolve_llm_context).to be_nil
    end

    it "returns nil when connector record is missing" do
      pref = described_class.new(llm_connector_id: 1)
      allow(pref).to receive(:llm_connector).and_return(nil)
      expect(pref.resolve_llm_context).to be_nil
    end
  end

  describe "#resolve_embedding_context" do
    it "returns nil without embedding connector" do
      pref = described_class.new
      expect(pref.resolve_embedding_context).to be_nil
    end

    it "returns context from embedding connector" do
      pref = create(:system_preference, :with_embedding)
      expect(pref.resolve_embedding_context).to be_present
    end

    it "returns nil when connector has no configurator" do
      connector = create(:connector, :llm_provider, :enabled)
      pref = described_class.new(embedding_connector: connector, embedding_model_id: "text-embedding-3-small")
      allow(connector).to receive(:configurator).and_return(nil)
      expect(pref.resolve_embedding_context).to be_nil
    end

    it "returns nil when connector record is missing" do
      pref = described_class.new(embedding_connector_id: 1)
      allow(pref).to receive(:embedding_connector).and_return(nil)
      expect(pref.resolve_embedding_context).to be_nil
    end
  end

  describe "#resolve_image_context" do
    it "returns nil without image connector" do
      pref = described_class.new
      expect(pref.resolve_image_context).to be_nil
    end

    it "returns context from image connector" do
      pref = create(:system_preference, :with_image)
      expect(pref.resolve_image_context).to be_present
    end

    it "returns nil when connector has no configurator" do
      connector = create(:connector, :llm_provider, :enabled)
      pref = described_class.new(image_connector: connector, image_model_id: "gpt-image-1")
      allow(connector).to receive(:configurator).and_return(nil)
      expect(pref.resolve_image_context).to be_nil
    end

    it "returns nil when connector record is missing" do
      pref = described_class.new(image_connector_id: 1)
      allow(pref).to receive(:image_connector).and_return(nil)
      expect(pref.resolve_image_context).to be_nil
    end
  end

  describe "cache invalidation" do
    it "invalidates cache on update" do
      pref = create(:system_preference, :configured)

      # Populate cache
      described_class.current_settings

      # Update triggers invalidation; re-fetching should reflect new value
      pref.update!(model_id: "gpt-4.1-mini")
      settings = described_class.current_settings
      expect(settings[:model_id]).to eq("gpt-4.1-mini")
    end
  end

  describe "tenant defaults" do
    it "assigns the current tenant on create when tenant is omitted" do
      tenant = create(:tenant)
      Current.tenant = tenant

      pref = described_class.create!

      expect(pref.tenant).to eq(tenant)
    ensure
      Current.reset
    end
  end
end
