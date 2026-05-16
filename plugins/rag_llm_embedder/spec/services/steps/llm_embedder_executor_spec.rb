# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Steps::LlmEmbedderExecutor do
  let(:config) { build(:rag_steps_llm_embedder, batch_size: 10, max_tokens_per_batch: 50_000) }
  let(:executor) { described_class.new(config, {}) }

  let(:embedding_response) do
    instance_double("RubyLLM::EmbeddingResponse", vectors: [[0.1, 0.2, 0.3]]) # rubocop:disable RSpec/VerifiedDoubleReference
  end

  before do
    allow(RubyLLM).to receive(:embed).and_return(embedding_response)
    # Prevent LLM connector from actually building context
    allow_any_instance_of(Connectors::LlmProvider).to receive(:build_context).and_return(nil) # rubocop:disable RSpec/AnyInstance
  end

  describe "#call" do
    it "returns documents unchanged when all chunks are empty" do
      doc = Rag::Document.new(id: "1", content: "Hello", metadata: {}, chunks: [])
      result = executor.call([doc])
      expect(result).to eq([doc])
      expect(RubyLLM).not_to have_received(:embed)
    end

    it "generates embeddings for all chunks" do
      chunk = Rag::Chunk.new(content: "some text", position: 0)
      doc = Rag::Document.new(id: "1", content: "Hello", metadata: {}, chunks: [chunk])
      allow(embedding_response).to receive(:vectors).and_return([[0.1, 0.2]])

      result = executor.call([doc])

      expect(RubyLLM).to have_received(:embed).with(["some text"], model: config.model_id)
      expect(result.first.chunks.first.embedding).to eq([0.1, 0.2])
    end

    it "maps embeddings back to the correct chunks across multiple documents" do
      vec1 = [0.1, 0.2]
      vec2 = [0.3, 0.4]
      allow(embedding_response).to receive(:vectors).and_return([vec1, vec2])

      chunk1 = Rag::Chunk.new(content: "chunk one", position: 0)
      chunk2 = Rag::Chunk.new(content: "chunk two", position: 1)
      doc1 = Rag::Document.new(id: "1", content: "doc1", chunks: [chunk1])
      doc2 = Rag::Document.new(id: "2", content: "doc2", chunks: [chunk2])

      result = executor.call([doc1, doc2])

      expect(result[0].chunks[0].embedding).to eq(vec1)
      expect(result[1].chunks[0].embedding).to eq(vec2)
    end

    it "handles response with embedding method instead of vectors" do
      allow(embedding_response).to receive(:respond_to?).with(:vectors).and_return(false)
      allow(embedding_response).to receive(:respond_to?).with(:embedding).and_return(true)
      allow(embedding_response).to receive(:embedding).and_return([0.9, 0.8])
      chunk = Rag::Chunk.new(content: "text", position: 0)
      doc = Rag::Document.new(id: "1", chunks: [chunk])

      result = executor.call([doc])

      expect(result.first.chunks.first.embedding).to eq([0.9, 0.8])
    end
  end

  describe "token-aware batching" do
    it "returns no batches when no chunk texts are present" do
      expect(executor.send(:token_aware_batches, [], config.batch_size, 10_000)).to eq([])
    end

    it "batches texts that would exceed the byte budget into separate API calls" do
      small_config = build(:rag_steps_llm_embedder, batch_size: 100, max_tokens_per_batch: 5)
      exec = described_class.new(small_config, {})
      chunks = [
        Rag::Chunk.new(content: "xxxx", position: 0),
        Rag::Chunk.new(content: "yyyy", position: 1),
      ]
      doc = Rag::Document.new(id: "1", chunks:)

      allow(embedding_response).to receive(:vectors).and_return([[0.1]], [[0.2]])
      allow(RubyLLM).to receive(:embed).and_return(embedding_response)

      exec.call([doc])

      expect(RubyLLM).to have_received(:embed).twice
    end

    it "splits oversized chunks before embedding them" do
      small_config = build(:rag_steps_llm_embedder, batch_size: 100, max_tokens_per_batch: 5)
      exec = described_class.new(small_config, {})
      chunk = Rag::Chunk.new(content: "abcdefghijk", position: 0)
      doc = Rag::Document.new(id: "1", chunks: [chunk])

      allow(embedding_response).to receive(:vectors).and_return([[0.1]], [[0.2]], [[0.3]])
      allow(RubyLLM).to receive(:embed).and_return(embedding_response)

      result = exec.call([doc])

      expect(RubyLLM).to have_received(:embed).with(["abcde"], model: small_config.model_id)
      expect(RubyLLM).to have_received(:embed).with(["fghij"], model: small_config.model_id)
      expect(RubyLLM).to have_received(:embed).with(["k"], model: small_config.model_id)
      expect(result.first.chunks.map(&:content)).to eq(["abcde", "fghij", "k"])
      expect(result.first.chunks.map(&:position)).to eq([0, 1, 2])
    end

    context "when the model context window is lower than the batch budget" do
      let(:connector) { create(:connector, :llm_provider, :enabled) }
      let(:model_limited_config) do
        build(
          :rag_steps_llm_embedder,
          :with_connector,
          llm_connector: connector,
          max_tokens_per_batch: 100,
        )
      end
      let(:model_limited_executor) { described_class.new(model_limited_config, {}) }
      let(:oversized_doc) { Rag::Document.new(id: "1", chunks: [Rag::Chunk.new(content: "abcdefghijk", position: 0)]) }

      before do
        create(
          :model,
          provider: connector.provider,
          model_id: model_limited_config.model_id,
          context_window: 5,
          modalities: { "input" => ["text"], "output" => ["embeddings"] },
        )
      end

      it "splits using the model context window" do
        allow(embedding_response).to receive(:vectors).and_return([[0.1], [0.2], [0.3]])
        allow(RubyLLM).to receive(:embed).and_return(embedding_response)

        result = model_limited_executor.call([oversized_doc])

        expect(RubyLLM).to have_received(:embed).with(
          ["abcde", "fghij", "k"],
          model: model_limited_config.model_id,
        )
        expect(result.first.chunks.map(&:content)).to eq(["abcde", "fghij", "k"])
      end
    end

    it "keeps oversized multibyte characters as standalone chunks" do
      tiny_config = build(:rag_steps_llm_embedder, batch_size: 100, max_tokens_per_batch: 1)
      exec = described_class.new(tiny_config, {})
      chunk = Rag::Chunk.new(content: "😀x", position: 0)
      doc = Rag::Document.new(id: "1", chunks: [chunk])

      allow(embedding_response).to receive(:vectors).and_return([[0.1]], [[0.2]])
      allow(RubyLLM).to receive(:embed).and_return(embedding_response)

      result = exec.call([doc])

      expect(RubyLLM).to have_received(:embed).with(["😀"], model: tiny_config.model_id)
      expect(RubyLLM).to have_received(:embed).with(["x"], model: tiny_config.model_id)
      expect(result.first.chunks.map(&:content)).to eq(["😀", "x"])
    end

    it "does not add an empty trailing chunk for a standalone oversized multibyte character" do
      tiny_config = build(:rag_steps_llm_embedder, batch_size: 100, max_tokens_per_batch: 1)
      exec = described_class.new(tiny_config, {})
      chunk = Rag::Chunk.new(content: "😀", position: 0)
      doc = Rag::Document.new(id: "1", chunks: [chunk])

      allow(embedding_response).to receive(:vectors).and_return([[0.1]])
      allow(RubyLLM).to receive(:embed).and_return(embedding_response)

      result = exec.call([doc])

      expect(RubyLLM).to have_received(:embed).with(["😀"], model: tiny_config.model_id)
      expect(result.first.chunks.map(&:content)).to eq(["😀"])
    end

    it "batches when item count exceeds batch_size" do
      small_config = build(:rag_steps_llm_embedder, batch_size: 1, max_tokens_per_batch: 100_000)
      exec = described_class.new(small_config, {})
      chunks = [
        Rag::Chunk.new(content: "chunk1", position: 0),
        Rag::Chunk.new(content: "chunk2", position: 1),
      ]
      doc = Rag::Document.new(id: "1", chunks:)
      allow(embedding_response).to receive(:vectors).and_return([[0.1]], [[0.2]])
      allow(RubyLLM).to receive(:embed).and_return(embedding_response)

      exec.call([doc])

      expect(RubyLLM).to have_received(:embed).twice
    end
  end

  describe "cancellation check" do
    it "raises CancelledError when run is cancelled" do
      run = create(:rag_run, :cancelled)
      exec = described_class.new(config, { run_id: run.id })
      chunk = Rag::Chunk.new(content: "text", position: 0)
      doc = Rag::Document.new(id: "1", chunks: [chunk])

      expect { exec.call([doc]) }.to raise_error(Rag::PipelineExecutor::CancelledError)
    end

    it "does not raise when run is not cancelled" do
      run = create(:rag_run, :running)
      exec = described_class.new(config, { run_id: run.id })
      chunk = Rag::Chunk.new(content: "text", position: 0)
      doc = Rag::Document.new(id: "1", chunks: [chunk])

      expect { exec.call([doc]) }.not_to raise_error
    end
  end

  describe "LLM context" do
    it "calls embed with context when llm_provider builds a non-nil context" do
      llm_connector = create(:connector, :llm_provider, :enabled)
      config_with_conn = build(:rag_steps_llm_embedder, llm_connector_id: llm_connector.id,
                                                        batch_size: 10, max_tokens_per_batch: 50_000,)
      exec = described_class.new(config_with_conn, {})
      llm_context_obj = double("LlmContext") # rubocop:disable RSpec/VerifiedDoubles
      allow_any_instance_of(Connectors::LlmProvider).to receive(:build_context).and_return(llm_context_obj) # rubocop:disable RSpec/AnyInstance

      chunk = Rag::Chunk.new(content: "text", position: 0)
      doc = Rag::Document.new(id: "1", chunks: [chunk])

      exec.call([doc])

      expect(RubyLLM).to have_received(:embed).with(
        ["text"],
        model: config_with_conn.model_id,
        context: llm_context_obj,
      )
    end

    it "calls embed without context when llm_connector is nil" do
      config_no_connector = build(:rag_steps_llm_embedder, batch_size: 10, max_tokens_per_batch: 50_000)
      allow(config_no_connector).to receive(:llm_connector).and_return(nil)
      exec = described_class.new(config_no_connector, {})

      chunk = Rag::Chunk.new(content: "text", position: 0)
      doc = Rag::Document.new(id: "1", chunks: [chunk])

      exec.call([doc])

      expect(RubyLLM).to have_received(:embed).with(["text"], model: config_no_connector.model_id)
    end

    it "calls embed without context when llm_connector cannot build context" do
      config_without_context_builder = build(:rag_steps_llm_embedder, batch_size: 10, max_tokens_per_batch: 50_000)
      connector_without_context_builder = double("ConnectorWithoutContextBuilder", provider: nil) # rubocop:disable RSpec/VerifiedDoubles
      allow(config_without_context_builder).to receive(:llm_connector).and_return(connector_without_context_builder)
      exec = described_class.new(config_without_context_builder, {})

      chunk = Rag::Chunk.new(content: "text", position: 0)
      doc = Rag::Document.new(id: "1", chunks: [chunk])

      exec.call([doc])

      expect(RubyLLM).to have_received(:embed).with(
        ["text"],
        model: config_without_context_builder.model_id,
      )
    end
  end

  describe "embed response fallback" do
    it "falls back to Array(response) when response has neither :vectors nor :embedding" do
      fallback_response = [[0.5, 0.6, 0.7]]
      allow(RubyLLM).to receive(:embed).and_return(fallback_response)

      # fallback_response.respond_to?(:vectors) => false, respond_to?(:embedding) => false
      # so Array(fallback_response) = [[0.5, 0.6, 0.7]] as the result
      chunk = Rag::Chunk.new(content: "text", position: 0)
      doc = Rag::Document.new(id: "1", chunks: [chunk])

      result = executor.call([doc])
      # The embedding should be [0.5, 0.6, 0.7] (first element of the fallback array)
      expect(result.first.chunks.first.embedding).to eq([0.5, 0.6, 0.7])
    end
  end

  describe "#build_llm_context when config lacks :llm_connector method" do
    it "uses Connector.find_by with llm_connector_id when config does not respond to :llm_connector" do
      allow(config).to receive(:respond_to?).and_call_original
      allow(config).to receive(:respond_to?).with(:llm_connector).and_return(false)
      allow(config).to receive(:llm_connector_id).and_return(nil)

      chunk = Rag::Chunk.new(content: "text", position: 0)
      doc = Rag::Document.new(id: "1", chunks: [chunk])

      executor.call([doc])

      expect(RubyLLM).to have_received(:embed).with(["text"], model: config.model_id)
    end
  end
end
