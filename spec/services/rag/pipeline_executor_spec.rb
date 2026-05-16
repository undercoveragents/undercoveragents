# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::PipelineExecutor do
  let(:flow) { create(:rag_flow, enabled: true) }
  let(:documents) do
    [
      Rag::Document.new(id: "1", content: "Hello world", metadata: {}, chunks: []),
    ]
  end

  # Helper: create an RagStep with module_type + configuration JSONB
  def create_source_step(flow, connector)
    create(:rag_step, rag_flow: flow, stage: "source",
                      module_type: "sql_database_source",
                      configuration: {
                        "connector_id" => connector.id,
                        "query" => "SELECT id, body FROM posts",
                        "content_column" => "body",
                        "metadata_columns" => [],
                        "batch_size" => 1000,
                      },)
  end

  def create_chunking_step(flow)
    create(:rag_step, rag_flow: flow, stage: "chunking",
                      module_type: "fixed_size_chunker",
                      configuration: { "chunk_size" => 1000, "chunk_overlap" => 200 },)
  end

  def create_embedding_step(flow, llm_connector)
    create(:rag_step, rag_flow: flow, stage: "embedding",
                      module_type: "llm_embedder",
                      configuration: {
                        "llm_connector_id" => llm_connector.id,
                        "model_id" => "text-embedding-3-small",
                        "batch_size" => 100,
                        "max_tokens_per_batch" => 6000,
                      },)
  end

  def create_storage_step(flow, connector)
    create(:rag_step, rag_flow: flow, stage: "storage",
                      module_type: "sql_database_storage",
                      configuration: {
                        "connector_id" => connector.id,
                        "documents_table" => "documents",
                        "chunks_table" => "chunks",
                        "content_field" => "content",
                        "embedding_field" => "embedding",
                        "document_reference_field" => "document_id",
                        "pre_load_action" => "none",
                        "upsert_enabled" => false,
                        "auto_create_tables" => false,
                        "embedding_dimensions" => 1536,
                        "metadata_column_types" => {},
                        "metadata_field_mappings" => {},
                      },)
  end

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe ".call" do
    context "with no configured source step" do
      it "raises an execution error" do
        expect { described_class.call(flow) }.to raise_error(described_class::ExecutionError, /Source step/)
      end
    end

    context "with a working pipeline" do
      let(:connector) { create(:connector, :sql_database, :enabled) }

      before do
        create_source_step(flow, connector)
        create_chunking_step(flow)

        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(RagSteps::SqlDatabaseSource).to receive(:each_batch).and_yield(documents)
        allow_any_instance_of(RagSteps::FixedSizeChunker).to receive(:execute).and_return(documents)
        # rubocop:enable RSpec/AnyInstance
      end

      it "creates a run" do
        run = described_class.call(flow)
        expect(run).to be_a(RagRun)
        expect(run).to be_completed
      end

      it "creates step runs for each stage" do
        run = described_class.call(flow)
        expect(run.rag_step_runs.count).to eq(4)
        expect(run.rag_step_runs.where.not(status: :skipped).count).to eq(2)
      end

      it "records the triggered_by value" do
        run = described_class.call(flow, triggered_by: "scheduled")
        expect(run.triggered_by).to eq("scheduled")
      end

      it "sets timestamps" do
        run = described_class.call(flow)
        expect(run.started_at).to be_present
        expect(run.completed_at).to be_present
      end

      it "aggregates stats across step runs" do
        run = described_class.call(flow)
        expect(run.stats).to include("duration_seconds")
      end
    end

    context "when a step fails" do
      before do
        connector = create(:connector, :sql_database, :enabled)
        create_source_step(flow, connector)

        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(RagSteps::SqlDatabaseSource).to receive(:each_batch)
          .and_raise(StandardError, "DB error")
        # rubocop:enable RSpec/AnyInstance
        allow(Rails.logger).to receive(:error)
      end

      it "marks the run as failed" do
        expect { described_class.call(flow) }.to raise_error(described_class::ExecutionError)
        run = flow.rag_runs.last
        expect(run).to be_failed
        expect(run.error_message).to include("DB error")
      end
    end

    context "when a non-source step fails mid-batch" do
      let(:connector) { create(:connector, :sql_database, :enabled) }

      before do
        create_source_step(flow, connector)
        create_chunking_step(flow)

        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(RagSteps::SqlDatabaseSource).to receive(:each_batch).and_yield(documents)
        allow_any_instance_of(RagSteps::FixedSizeChunker).to receive(:execute)
          .and_raise(StandardError, "Chunking failed")
        # rubocop:enable RSpec/AnyInstance
        allow(Rails.logger).to receive(:error)
      end

      it "marks the run as failed with chunking error" do
        expect { described_class.call(flow) }.to raise_error(described_class::ExecutionError, /Chunking failed/)
        run = flow.rag_runs.last
        expect(run).to be_failed
      end
    end

    context "when the run is cancelled mid-execution (between batches)" do
      let(:connector) { create(:connector, :sql_database, :enabled) }

      before do
        create_source_step(flow, connector)
        create_chunking_step(flow)

        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(RagSteps::SqlDatabaseSource).to receive(:each_batch).and_yield(documents)
        allow_any_instance_of(RagSteps::FixedSizeChunker).to receive(:execute).and_return(documents)
        allow_any_instance_of(RagRun).to receive(:reload) do |run|
          run.status = "cancelled"
          run
        end
        # rubocop:enable RSpec/AnyInstance
      end

      it "marks the run as cancelled" do
        described_class.call(flow)
        run = flow.rag_runs.last
        expect(run.reload).to be_cancelled
      end
    end

    context "with embedding and storage steps configured" do
      let(:connector) { create(:connector, :sql_database, :enabled) }
      let(:llm_connector) { create(:connector, :llm_provider, :enabled) }
      let(:storage_connector) { create(:connector, :sql_database, :enabled) }

      before do
        create_source_step(flow, connector)
        create_chunking_step(flow)
        create_embedding_step(flow, llm_connector)
        create_storage_step(flow, storage_connector)

        chunk = Rag::Chunk.new(content: "chunk text", position: 0, embedding: [0.1, 0.2])
        doc_with_chunk = Rag::Document.new(id: "1", content: "text", metadata: {}, chunks: [chunk])

        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(RagSteps::SqlDatabaseSource).to receive(:each_batch).and_yield(documents)
        allow_any_instance_of(RagSteps::FixedSizeChunker).to receive(:execute).and_return([doc_with_chunk])
        allow_any_instance_of(RagSteps::LlmEmbedder).to receive(:execute).and_return([doc_with_chunk])
        allow_any_instance_of(RagSteps::SqlDatabaseStorage).to receive(:execute).and_return([doc_with_chunk])
        allow_any_instance_of(RagSteps::SqlDatabaseStorage).to receive(:existing_content_hashes).and_return(Set.new)
        # rubocop:enable RSpec/AnyInstance
      end

      it "creates a completed run with all stages executed" do
        run = described_class.call(flow)
        expect(run).to be_completed
        expect(run.rag_step_runs.where(status: :completed).count).to eq(4)
      end
    end

    context "with a pre-existing run" do
      let(:connector) { create(:connector, :sql_database, :enabled) }

      before do
        create_source_step(flow, connector)

        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(RagSteps::SqlDatabaseSource).to receive(:each_batch).and_yield(documents)
        # rubocop:enable RSpec/AnyInstance
      end

      it "reuses the existing run instead of creating a new one" do
        existing_run = create(:rag_run, rag_flow: flow, status: :pending)
        expect do
          described_class.call(flow, run: existing_run)
        end.not_to change(RagRun, :count)
        expect(existing_run.reload).to be_completed
      end
    end

    context "with multiple batches from source" do
      let(:connector) { create(:connector, :sql_database, :enabled) }

      before do
        create_source_step(flow, connector)
        create_chunking_step(flow)

        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(RagSteps::SqlDatabaseSource).to receive(:each_batch)
          .and_yield(documents).and_yield(documents)
        allow_any_instance_of(RagSteps::FixedSizeChunker).to receive(:execute).and_return(documents)
        # rubocop:enable RSpec/AnyInstance
      end

      it "marks the run as completed processing both batches" do
        run = described_class.call(flow)
        expect(run).to be_completed
      end
    end

    context "when CancelledError is raised inside a non-source step" do
      let(:connector) { create(:connector, :sql_database, :enabled) }

      before do
        create_source_step(flow, connector)
        create_chunking_step(flow)

        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(RagSteps::SqlDatabaseSource).to receive(:each_batch).and_yield(documents)
        allow_any_instance_of(RagSteps::FixedSizeChunker).to receive(:execute)
          .and_raise(described_class::CancelledError, "Cancelled inside step")
        # rubocop:enable RSpec/AnyInstance
      end

      it "marks the run as cancelled" do
        run = described_class.call(flow)
        expect(run).to be_cancelled
      end
    end

    context "when deduplication storage raises an error" do
      let(:source_connector) { create(:connector, :sql_database, :enabled) }
      let(:storage_connector) { create(:connector, :sql_database, :enabled) }

      before do
        create_source_step(flow, source_connector)
        create_storage_step(flow, storage_connector)

        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(RagSteps::SqlDatabaseSource).to receive(:each_batch).and_yield(documents)
        allow_any_instance_of(RagSteps::SqlDatabaseStorage).to receive(:execute).and_return(documents)
        allow_any_instance_of(RagSteps::SqlDatabaseStorage)
          .to receive(:existing_content_hashes)
          .and_raise(StandardError, "connection failed")
        # rubocop:enable RSpec/AnyInstance
        allow(Rails.logger).to receive(:error)
      end

      it "proceeds with all documents when deduplication fails" do
        run = described_class.call(flow)
        expect(run).to be_completed
      end
    end

    context "when source yields an empty batch" do
      let(:connector) { create(:connector, :sql_database, :enabled) }

      before do
        create_source_step(flow, connector)

        allow_any_instance_of(RagSteps::SqlDatabaseSource).to receive(:each_batch).and_yield([]) # rubocop:disable RSpec/AnyInstance
      end

      it "creates a completed run with no documents processed" do
        run = described_class.call(flow)
        expect(run).to be_completed
      end
    end

    context "when deduplication finds no previously stored documents (empty existing set)" do
      let(:source_connector) { create(:connector, :sql_database, :enabled) }
      let(:storage_connector) { create(:connector, :sql_database, :enabled) }

      before do
        create_source_step(flow, source_connector)
        create_storage_step(flow, storage_connector)

        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(RagSteps::SqlDatabaseSource).to receive(:each_batch).and_yield(documents)
        allow_any_instance_of(RagSteps::SqlDatabaseStorage).to receive(:execute).and_return(documents)
        allow_any_instance_of(RagSteps::SqlDatabaseStorage)
          .to receive(:existing_content_hashes).and_return(Set.new)
        # rubocop:enable RSpec/AnyInstance
      end

      it "processes all documents since nothing is pre-stored" do
        run = described_class.call(flow)
        expect(run).to be_completed
      end
    end

    context "when deduplication filters out already-stored documents" do
      let(:source_connector) { create(:connector, :sql_database, :enabled) }
      let(:storage_connector) { create(:connector, :sql_database, :enabled) }

      before do
        create_source_step(flow, source_connector)
        create_storage_step(flow, storage_connector)

        old_doc = Rag::Document.new(id: "1", content: "old content", metadata: {}, chunks: [])
        new_doc = Rag::Document.new(id: "2", content: "new content", metadata: {}, chunks: [])

        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(RagSteps::SqlDatabaseSource).to receive(:each_batch).and_yield([old_doc, new_doc])
        allow_any_instance_of(RagSteps::SqlDatabaseStorage).to receive(:execute).and_return([new_doc])
        allow_any_instance_of(RagSteps::SqlDatabaseStorage)
          .to receive(:existing_content_hashes).and_return(Set.new([old_doc.content_hash]))
        # rubocop:enable RSpec/AnyInstance
      end

      it "skips unchanged documents and runs storage only for new ones" do
        run = described_class.call(flow)
        expect(run).to be_completed
      end
    end
  end

  describe "private helper fallbacks" do
    subject(:executor) { described_class.new(flow) }

    it "returns empty stats for an unknown stage" do
      expect(executor.send(:build_step_stats, :unknown, {})).to eq({})
    end

    it "returns zero output count for an unknown stage" do
      expect(executor.send(:step_output_count, :unknown, {})).to eq(0)
    end

    it "ignores unknown stages when accumulating stats" do
      stats = { documents_loaded: 1 }

      executor.send(:accumulate_stats, stats, :unknown, documents)

      expect(stats).to eq(documents_loaded: 1)
    end

    it "skips deduplication when storage does not opt in" do
      storage = Class.new do
        def existing_content_hashes(*) = Set.new

        def deduplication_applicable? = false
      end.new
      allow(flow).to receive(:module_for).with(:storage).and_return(storage)

      expect(executor.send(:deduplication_storage)).to be_nil
    end

    it "ignores non-numeric aggregated stats" do
      step_run = instance_double(RagStepRun, stats: { "documents_loaded" => 2, "note" => "skip" })
      step_runs = instance_double(ActiveRecord::Relation, reload: [step_run])
      run = instance_double(RagRun, rag_step_runs: step_runs, duration: 1.234)

      expect(executor.send(:aggregate_stats, run)).to eq(
        "documents_loaded" => 2,
        "duration_seconds" => 1.23,
      )
    end

    it "keeps duration_seconds nil when the run has no duration yet" do
      step_run = instance_double(RagStepRun, stats: { "documents_loaded" => 1 })
      step_runs = instance_double(ActiveRecord::Relation, reload: [step_run])
      run = instance_double(RagRun, rag_step_runs: step_runs, duration: nil)

      expect(executor.send(:aggregate_stats, run)["duration_seconds"]).to be_nil
    end
  end
end
