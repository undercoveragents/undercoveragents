# frozen_string_literal: true

# == Schema Information
#
# Table name: rag_step_runs
# Database name: primary
#
#  id            :bigint           not null, primary key
#  completed_at  :datetime
#  error_message :text
#  input_count   :integer          default(0), not null
#  output_count  :integer          default(0), not null
#  position      :integer          not null
#  started_at    :datetime
#  stats         :jsonb            not null
#  status        :string           default("pending"), not null
#  step_type     :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  rag_run_id    :bigint           not null
#
# Indexes
#
#  idx_step_runs_on_run_and_type      (rag_run_id,step_type) UNIQUE
#  index_rag_step_runs_on_rag_run_id  (rag_run_id)
#
# Foreign Keys
#
#  fk_rails_...  (rag_run_id => rag_runs.id)
#
require "rails_helper"

RSpec.describe RagStepRun do
  describe "associations" do
    it { is_expected.to belong_to(:rag_run).inverse_of(:rag_step_runs) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:step_type) }
    it { is_expected.to validate_inclusion_of(:step_type).in_array(RagStepRun::STEP_TYPES) }
    it { is_expected.to validate_presence_of(:position) }
    it { is_expected.to validate_numericality_of(:position).only_integer.is_greater_than(0) }
  end

  describe "enums" do
    subject(:step_run) { described_class.new }

    it {
      expect(step_run).to define_enum_for(:status).backed_by_column_of_type(:string).with_values(
        pending: "pending",
        running: "running",
        completed: "completed",
        failed: "failed",
        skipped: "skipped",
      )
    }
  end

  describe "#duration" do
    let(:run) { create(:rag_run) }

    it "returns nil when not started" do
      step_run = create(:rag_step_run, rag_run: run, started_at: nil)
      expect(step_run.duration).to be_nil
    end

    it "returns elapsed seconds when completed" do
      step_run = create(:rag_step_run, rag_run: run, started_at: 10.seconds.ago,
                                       completed_at: 5.seconds.ago,)
      expect(step_run.duration).to be_within(1).of(5)
    end
  end

  describe "#finished?" do
    let(:run) { create(:rag_run) }

    it "returns true when completed" do
      expect(create(:rag_step_run, :completed, rag_run: run)).to be_finished
    end

    it "returns true when failed" do
      expect(create(:rag_step_run, :failed, rag_run: run)).to be_finished
    end

    it "returns true when skipped" do
      expect(create(:rag_step_run, :skipped, rag_run: run)).to be_finished
    end

    it "returns false when pending" do
      expect(create(:rag_step_run, :pending, rag_run: run)).not_to be_finished
    end
  end

  describe "#step_label" do
    it "returns the label from RagFlow::STAGES" do
      step_run = build(:rag_step_run, step_type: "source")
      expect(step_run.step_label).to eq("Document Rag")
    end

    it "returns titleized type for unknown types" do
      step_run = build(:rag_step_run, step_type: "unknown")
      expect(step_run.step_label).to eq("Unknown")
    end
  end

  describe "#step_icon" do
    it "returns the icon from RagFlow::STAGES" do
      step_run = build(:rag_step_run, step_type: "chunking")
      expect(step_run.step_icon).to eq("fa-solid fa-scissors")
    end

    it "returns the default icon for an unknown step type" do
      step_run = build(:rag_step_run, step_type: "chunking")
      allow(step_run).to receive(:step_type).and_return("unknown_stage")
      expect(step_run.step_icon).to eq("fa-solid fa-circle")
    end
  end

  describe "#step_stage_key" do
    it "returns the step_type as a string" do
      step_run = build(:rag_step_run, step_type: "embedding")
      expect(step_run.step_stage_key).to eq("embedding")
    end
  end

  describe "#primary_stat_value" do
    it "returns output_count" do
      step_run = build(:rag_step_run, step_type: "source", output_count: 42)
      expect(step_run.primary_stat_value).to eq(42)
    end
  end

  describe "#primary_stat_label" do
    it "returns 'documents' for source" do
      step_run = build(:rag_step_run, step_type: "source")
      expect(step_run.primary_stat_label).to eq("documents")
    end

    it "returns 'chunks' for chunking" do
      step_run = build(:rag_step_run, step_type: "chunking")
      expect(step_run.primary_stat_label).to eq("chunks")
    end

    it "returns 'embeddings' for embedding" do
      step_run = build(:rag_step_run, step_type: "embedding")
      expect(step_run.primary_stat_label).to eq("embeddings")
    end

    it "returns 'stored' for storage" do
      step_run = build(:rag_step_run, step_type: "storage")
      expect(step_run.primary_stat_label).to eq("stored")
    end

    it "returns 'records' for an unrecognised step type" do
      step_run = build(:rag_step_run, step_type: "source")
      allow(step_run).to receive(:step_type).and_return("other")
      expect(step_run.primary_stat_label).to eq("records")
    end
  end

  describe "#module_label" do
    it "returns nil when no step is configured for the stage" do
      run = create(:rag_run)
      step_run = create(:rag_step_run, rag_run: run, step_type: "source")
      expect(step_run.module_label).to be_nil
    end

    it "returns the module type label when a step is configured for the stage" do
      flow = create(:rag_flow)
      create(:rag_step, rag_flow: flow, stage: "storage",
                        module_type: "sql_database_storage",
                        configuration: { "connector_id" => nil, "documents_table" => "docs",
                                         "chunks_table" => "chunks", "content_field" => "content",
                                         "embedding_field" => "embedding",
                                         "document_reference_field" => "document_id",
                                         "pre_load_action" => "none", },)
      run = create(:rag_run, rag_flow: flow)
      step_run = create(:rag_step_run, rag_run: run, step_type: "storage")
      expect(step_run.module_label).to eq("SQL Database")
    end
  end

  describe "#skipped_count" do
    it "returns documents_skipped for source steps" do
      step_run = build(:rag_step_run, step_type: "source", stats: { "documents_skipped" => 5 })
      expect(step_run.skipped_count).to eq(5)
    end

    it "returns nil for non-source steps" do
      step_run = build(:rag_step_run, step_type: "chunking")
      expect(step_run.skipped_count).to be_nil
    end
  end
end
