# frozen_string_literal: true

require "rails_helper"

RSpec.describe RagSteps::LlmEmbedder do
  describe "validations" do
    subject(:embedder) { build(:rag_steps_llm_embedder) }

    it { is_expected.to validate_presence_of(:model_id) }
    it { is_expected.to validate_presence_of(:batch_size) }
    it { is_expected.to validate_presence_of(:max_tokens_per_batch) }

    it "validates batch_size is greater than 0" do
      embedder.batch_size = 0
      embedder.valid?
      expect(embedder.errors[:batch_size]).to include("must be greater than 0")
    end

    it "validates dimensions is greater than 0" do
      embedder.dimensions = 0
      embedder.valid?
      expect(embedder.errors[:dimensions]).to include("must be greater than 0")
    end

    it "allows dimensions to be nil" do
      embedder.dimensions = nil
      embedder.valid?
      expect(embedder.errors[:dimensions]).to be_empty
    end

    describe "llm_connector_must_be_llm_provider" do
      it "is invalid with a non-LLM-provider connector" do
        sql_connector = create(:connector, :sql_database)
        embedder = build(:rag_steps_llm_embedder, llm_connector_id: sql_connector.id)
        expect(embedder).not_to be_valid
        expect(embedder.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
      end

      it "skips validation when llm_connector_id is blank" do
        embedder = build(:rag_steps_llm_embedder, llm_connector_id: nil)
        embedder.valid?
        expect(embedder.errors[:llm_connector_id]).not_to include("must be an LLM Provider connector")
      end

      it "adds error when connector is not found" do
        embedder = build(:rag_steps_llm_embedder, llm_connector_id: 999_999)
        expect(embedder).not_to be_valid
        expect(embedder.errors[:llm_connector_id]).to include("connector not found")
      end

      it "passes validation with a valid LLM provider connector" do
        connector = create(:connector, :llm_provider, :enabled)
        embedder = build(:rag_steps_llm_embedder, llm_connector_id: connector.id)
        embedder.valid?
        expect(embedder.errors[:llm_connector_id]).to be_empty
      end

      it "rejects connectors outside the rag flow tenant" do
        tenant = create(:tenant)
        rag_flow = create(:rag_flow, operation: create(:operation, tenant:))
        foreign_connector = create(:connector, :llm_provider, :enabled, tenant: create(:tenant))
        rag_step = create(
          :rag_step,
          rag_flow:,
          stage: "embedding",
          module_type: "llm_embedder",
          configuration: {
            "llm_connector_id" => foreign_connector.id,
            "model_id" => "text-embedding-3-small",
            "batch_size" => 100,
            "max_tokens_per_batch" => 6000,
          },
        )
        embedder = rag_step.configurator

        expect(embedder).not_to be_valid
        expect(embedder.errors[:llm_connector_id]).to include("connector not found")
      end
    end
  end

  describe ".key" do
    it { expect(described_class.key).to eq("llm_embedder") }
  end

  describe ".label" do
    it { expect(described_class.label).to eq("LLM Embedder") }
  end

  describe ".stage" do
    it { expect(described_class.stage).to eq(:embedding) }
  end

  describe ".build_from_params" do
    it "builds from params" do
      connector = create(:connector, :llm_provider, :enabled)
      params = ActionController::Parameters.new(
        llm_embedder: { llm_connector_id: connector.id, model_id: "text-embedding-3-small", batch_size: 50,
                        max_tokens_per_batch: 3000, },
      )
      embedder = described_class.build_from_params(params)
      expect(embedder.model_id).to eq("text-embedding-3-small")
    end
  end

  describe "#validate_configuration!" do
    it "raises when llm_connector is blank" do
      embedder = build(:rag_steps_llm_embedder, llm_connector_id: nil)
      expect { embedder.validate_configuration! }.to raise_error("LLM connector is required")
    end

    it "raises when model_id is blank" do
      connector = create(:connector, :llm_provider, :enabled)
      embedder = build(:rag_steps_llm_embedder, llm_connector_id: connector.id, model_id: nil)
      expect { embedder.validate_configuration! }.to raise_error("Model ID is required")
    end

    it "does not raise when fully configured" do
      connector = create(:connector, :llm_provider, :enabled)
      embedder = build(:rag_steps_llm_embedder, llm_connector_id: connector.id)
      expect { embedder.validate_configuration! }.not_to raise_error
    end
  end

  describe "#summary" do
    it "includes model_id and connector name" do
      connector = create(:connector, :llm_provider, :enabled, name: "OpenAI")
      embedder = build(:rag_steps_llm_embedder, llm_connector_id: connector.id, model_id: "ada-002",
                                                batch_size: 100,)
      expect(embedder.summary).to eq("ada-002 via OpenAI (batch: 100)")
    end

    it "uses 'unknown' when llm_connector is nil" do
      embedder = build(:rag_steps_llm_embedder, llm_connector_id: nil, model_id: "ada-002", batch_size: 50)
      expect(embedder.summary).to eq("ada-002 via unknown (batch: 50)")
    end
  end

  describe "#execute" do
    it "delegates to LlmEmbedderExecutor" do
      connector = create(:connector, :llm_provider, :enabled)
      embedder = build(:rag_steps_llm_embedder, llm_connector_id: connector.id)
      docs = []
      allow(Rag::Steps::LlmEmbedderExecutor).to receive(:new).and_call_original
      allow_any_instance_of(Rag::Steps::LlmEmbedderExecutor).to receive(:call).and_return([]) # rubocop:disable RSpec/AnyInstance
      embedder.execute(docs, {})
      expect(Rag::Steps::LlmEmbedderExecutor).to have_received(:new).with(embedder, {})
    end
  end

  describe ".icon" do
    it { expect(described_class.icon).to eq("fa-solid fa-vector-square") }
  end

  describe ".description" do
    it "returns a non-empty description" do
      expect(described_class.description).to include("LLM provider")
    end
  end

  describe ".permitted_params" do
    it "returns llm_embedder params" do
      params = ActionController::Parameters.new(
        llm_embedder: { llm_connector_id: "1", model_id: "text-embedding-3-small",
                        batch_size: "100", max_tokens_per_batch: "6000", dimensions: "1536", },
      )
      result = described_class.permitted_params(params)
      expect(result[:model_id]).to eq("text-embedding-3-small")
      expect(result[:dimensions]).to eq("1536")
    end
  end

  describe "#form_partial_path" do
    it "returns the expected partial path" do
      embedder = build(:rag_steps_llm_embedder)
      expect(File.directory?(embedder.form_partial_path)).to be(true)
      expect(File.exist?(File.join(embedder.form_partial_path, "_form.html.haml"))).to be(true)
    end
  end

  describe "#to_configuration" do
    it "returns a serializable hash" do
      embedder = build(:rag_steps_llm_embedder, model_id: "ada-002", batch_size: 100)
      config = embedder.to_configuration
      expect(config).to include("model_id" => "ada-002", "batch_size" => 100)
    end
  end

  describe "#llm_connector" do
    it "returns the connector when llm_connector_id is set" do
      connector = create(:connector, :llm_provider, :enabled)
      embedder = build(:rag_steps_llm_embedder, llm_connector_id: connector.id)
      expect(embedder.llm_connector).to eq(connector)
    end

    it "returns nil when llm_connector_id is nil" do
      embedder = build(:rag_steps_llm_embedder, llm_connector_id: nil)
      expect(embedder.llm_connector).to be_nil
    end

    it "memoizes the result" do
      connector = create(:connector, :llm_provider, :enabled)
      embedder = build(:rag_steps_llm_embedder, llm_connector_id: connector.id)
      first_call = embedder.llm_connector
      second_call = embedder.llm_connector
      expect(first_call).to equal(second_call)
    end
  end

  describe "constants" do
    it "defines APPROX_CHARS_PER_TOKEN" do
      expect(described_class::APPROX_CHARS_PER_TOKEN).to eq(4)
    end
  end
end
