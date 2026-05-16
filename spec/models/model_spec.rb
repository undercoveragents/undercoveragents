# frozen_string_literal: true

# == Schema Information
#
# Table name: models
# Database name: primary
#
#  id                :bigint           not null, primary key
#  capabilities      :jsonb
#  context_window    :integer
#  family            :string
#  knowledge_cutoff  :date
#  max_output_tokens :integer
#  metadata          :jsonb
#  modalities        :jsonb
#  model_created_at  :datetime
#  name              :string           not null
#  pricing           :jsonb
#  provider          :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  model_id          :string           not null
#
# Indexes
#
#  index_models_on_capabilities           (capabilities) USING gin
#  index_models_on_family                 (family)
#  index_models_on_modalities             (modalities) USING gin
#  index_models_on_provider               (provider)
#  index_models_on_provider_and_model_id  (provider,model_id) UNIQUE
#
require "rails_helper"

RSpec.describe Model do
  describe "factory" do
    it "creates a valid model" do
      model = create(:model)
      expect(model).to be_persisted
    end
  end

  describe "validations" do
    subject { build(:model) }

    it "requires a name" do
      model = build(:model, name: nil)
      expect(model).not_to be_valid
    end

    it "requires a provider" do
      model = build(:model, provider: nil)
      expect(model).not_to be_valid
    end

    it "requires a model_id" do
      model = build(:model, model_id: nil)
      expect(model).not_to be_valid
    end

    it "enforces unique provider + model_id" do
      create(:model, provider: "openai", model_id: "gpt-4.1")
      duplicate = build(:model, provider: "openai", model_id: "gpt-4.1")
      expect(duplicate).not_to be_valid
    end
  end

  describe ".refresh!" do
    let(:model_info) do
      instance_double(
        RubyLLM::Model::Info,
        id: "gpt-4.1",
        name: "GPT-4.1",
        provider: "openai",
        family: "gpt",
        created_at: nil,
        context_window: 128_000,
        max_output_tokens: 4096,
        knowledge_cutoff: nil,
        modalities: RubyLLM::Model::Modalities.new({ input: ["text"], output: ["text"] }),
        capabilities: ["function_calling", "streaming"],
        pricing: RubyLLM::Model::Pricing.new({}),
        metadata: { "temperature" => true, "open_weights" => false },
      )
    end

    before do
      allow(RubyLLM.models).to receive(:refresh!)
      allow(RubyLLM.models).to receive(:all).and_return([model_info])
    end

    it "adds temperature capability when metadata indicates support" do
      described_class.refresh!
      model = described_class.find_by(model_id: "gpt-4.1", provider: "openai")
      expect(model.capabilities).to include("temperature")
    end

    it "does not add open_weights capability when metadata is false" do
      described_class.refresh!
      model = described_class.find_by(model_id: "gpt-4.1", provider: "openai")
      expect(model.capabilities).not_to include("open_weights")
    end
  end

  describe "metadata-based capabilities" do
    it "adds open_weights capability when metadata indicates open weights" do
      model_info = instance_double(
        RubyLLM::Model::Info,
        id: "llama-3.3-70b",
        name: "Llama 3.3 70B",
        provider: "bedrock",
        family: "llama",
        created_at: nil,
        context_window: 128_000,
        max_output_tokens: 4096,
        knowledge_cutoff: nil,
        modalities: RubyLLM::Model::Modalities.new({ input: ["text"], output: ["text"] }),
        capabilities: ["function_calling"],
        pricing: RubyLLM::Model::Pricing.new({}),
        metadata: { "temperature" => true, "open_weights" => true },
      )
      allow(RubyLLM.models).to receive(:refresh!)
      allow(RubyLLM.models).to receive(:all).and_return([model_info])

      described_class.refresh!
      model = described_class.find_by(model_id: "llama-3.3-70b", provider: "bedrock")
      expect(model.capabilities).to include("temperature", "open_weights")
    end

    it "adds metadata-driven capabilities when metadata uses symbol keys" do
      model_info = instance_double(
        RubyLLM::Model::Info,
        id: "gpt-oss-120b",
        name: "GPT OSS 120B",
        provider: "openai",
        family: "gpt-oss",
        created_at: nil,
        context_window: 128_000,
        max_output_tokens: 4096,
        knowledge_cutoff: nil,
        modalities: RubyLLM::Model::Modalities.new({ input: ["text"], output: ["text"] }),
        capabilities: ["streaming"],
        pricing: RubyLLM::Model::Pricing.new({}),
        metadata: { temperature: true, open_weights: true },
      )
      allow(RubyLLM.models).to receive(:refresh!)
      allow(RubyLLM.models).to receive(:all).and_return([model_info])

      described_class.refresh!
      model = described_class.find_by(model_id: "gpt-oss-120b", provider: "openai")

      expect(model.capabilities).to include("temperature", "open_weights")
    end

    it "keeps temperature support when metadata uses symbol keys directly" do
      capabilities = described_class.send(:enrich_capabilities, ["streaming"], { temperature: true })

      expect(capabilities).to include("streaming", "temperature")
    end

    it "does not add temperature support when metadata does not expose it" do
      capabilities = described_class.send(:enrich_capabilities, ["streaming"], {})

      expect(capabilities).to eq(["streaming"])
    end
  end

  describe "capability helpers" do
    it "reports temperature and reasoning support from capabilities" do
      model = build(:model, capabilities: ["temperature", "reasoning"])

      expect(model.supports_temperature?).to be(true)
      expect(model.supports_reasoning?).to be(true)
      expect(model.supports_capability?("reasoning")).to be(true)
    end

    it "returns false when a capability is missing" do
      model = build(:model, capabilities: ["streaming"])

      expect(model.supports_temperature?).to be(false)
      expect(model.supports_reasoning?).to be(false)
    end

    it "derives attachment support from input modalities" do
      model = build(:model, modalities: { "input" => ["text", "image", "pdf"], "output" => ["text"] })

      expect(model.supports_attachments?).to be(true)
      expect(model.attachment_input_modalities).to eq(["image", "pdf"])
      expect(model.attachment_accept).to eq("image/*,application/pdf")
    end

    it "does not treat text-only models as attachment-capable" do
      model = build(:model, modalities: { "input" => ["text"], "output" => ["text"] })

      expect(model.supports_attachments?).to be(false)
      expect(model.attachment_accept).to be_nil
      expect(model.supports_attachment_content_type?("image/png")).to be(false)
    end

    it "handles missing modality metadata" do
      model = build(:model, modalities: nil)

      expect(model.model_input_modalities).to eq([])
    end

    it "falls back to image attachments for legacy vision-only model data" do
      model = build(:model, capabilities: ["vision"], modalities: {})

      expect(model.attachment_input_modalities).to eq(["image"])
      expect(model.attachment_accept).to eq("image/*")
    end

    it "matches uploaded attachment content types against accepted modalities" do
      model = build(:model, modalities: { "input" => ["image", "pdf"], "output" => ["text"] })

      expect(model.supports_attachment_content_type?("image/png")).to be(true)
      expect(model.supports_attachment_content_type?("application/pdf")).to be(true)
      expect(model.supports_attachment_content_type?("text/plain")).to be(false)
    end
  end
end
