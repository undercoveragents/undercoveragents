# frozen_string_literal: true

# == Schema Information
#
# Table name: rag_flows
# Database name: primary
#
#  id           :bigint           not null, primary key
#  enabled      :boolean          default(TRUE), not null
#  name         :string           not null
#  slug         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  operation_id :bigint           not null
#
# Indexes
#
#  index_rag_flows_on_operation_id           (operation_id)
#  index_rag_flows_on_operation_id_and_name  (operation_id,name) UNIQUE
#  index_rag_flows_on_slug                   (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
require "rails_helper"

RSpec.describe RagFlow do
  describe "associations" do
    it { is_expected.to have_many(:rag_steps).dependent(:destroy) }
    it { is_expected.to have_many(:rag_runs).dependent(:destroy) }

    it { is_expected.to have_one(:source_step).class_name("RagStep").conditions(stage: "source") }
    it { is_expected.to have_one(:chunking_step).class_name("RagStep").conditions(stage: "chunking") }
    it { is_expected.to have_one(:embedding_step).class_name("RagStep").conditions(stage: "embedding") }
    it { is_expected.to have_one(:storage_step).class_name("RagStep").conditions(stage: "storage") }
  end

  describe "validations" do
    subject { create(:rag_flow) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:operation_id).case_insensitive }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
  end

  describe "scopes" do
    let!(:enabled_pipeline) { create(:rag_flow, enabled: true) }
    let!(:disabled_pipeline) { create(:rag_flow, enabled: false) }

    describe ".enabled" do
      it "returns only enabled pipelines" do
        expect(described_class.enabled).to contain_exactly(enabled_pipeline)
        expect(described_class.enabled).not_to include(disabled_pipeline)
      end
    end

    describe ".ordered" do
      it "orders by name" do
        expect(described_class.ordered).to eq(described_class.order(:name))
      end
    end
  end

  describe "#runnable?" do
    it "returns true when enabled" do
      pipeline = create(:rag_flow, enabled: true)
      expect(pipeline.runnable?).to be true
    end

    it "returns false when disabled" do
      pipeline = create(:rag_flow, enabled: false)
      expect(pipeline.runnable?).to be false
    end
  end

  describe "#step_for" do
    let(:flow) { create(:rag_flow) }

    it "returns the step record for a given stage" do
      step = create(:rag_step, rag_flow: flow, stage: "chunking",
                               module_type: "fixed_size_chunker",
                               configuration: { "chunk_size" => 1000, "chunk_overlap" => 200 },)
      expect(flow.step_for(:chunking)).to eq(step)
    end

    it "returns nil when stage is not configured" do
      expect(flow.step_for(:chunking)).to be_nil
    end
  end

  describe "#module_for" do
    let(:flow) { create(:rag_flow) }

    it "returns the configurator for a stage" do
      create(:rag_step, rag_flow: flow, stage: "chunking",
                        module_type: "fixed_size_chunker",
                        configuration: { "chunk_size" => 1000, "chunk_overlap" => 200 },)
      configurator = flow.module_for(:chunking)
      expect(configurator).to be_a(RagSteps::FixedSizeChunker)
      expect(configurator.chunk_size).to eq(1000)
    end

    it "returns nil when stage is not configured" do
      expect(flow.module_for(:chunking)).to be_nil
    end
  end

  describe "#stage_configured?" do
    let(:flow) { create(:rag_flow) }

    it "returns true when stage has a step configured" do
      create(:rag_step, rag_flow: flow, stage: "chunking",
                        module_type: "fixed_size_chunker",
                        configuration: { "chunk_size" => 1000, "chunk_overlap" => 200 },)
      expect(flow.stage_configured?(:chunking)).to be true
    end

    it "returns false when stage does not have a step configured" do
      expect(flow.stage_configured?(:chunking)).to be false
    end
  end

  describe "#fully_configured?" do
    it "returns true when all 4 stages are configured" do
      flow = create(:rag_flow, :with_steps)
      expect(flow.fully_configured?).to be true
    end

    it "returns false when not all stages are configured" do
      flow = create(:rag_flow)
      create(:rag_step, rag_flow: flow, stage: "chunking",
                        module_type: "fixed_size_chunker",
                        configuration: { "chunk_size" => 1000, "chunk_overlap" => 200 },)
      expect(flow.fully_configured?).to be false
    end
  end

  describe "#ordered_stages" do
    let(:flow) { create(:rag_flow, :with_steps) }

    it "returns all 4 stages in order" do
      stages = flow.ordered_stages
      expect(stages.length).to eq(4)
      expect(stages.first.first[:key]).to eq(:source)
      expect(stages.last.first[:key]).to eq(:storage)
    end
  end

  describe ".stage_config" do
    it "returns the config for a given stage key" do
      config = described_class.stage_config(:chunking)
      expect(config[:label]).to eq("Chunking")
      expect(config[:icon]).to eq("fa-solid fa-scissors")
    end

    it "returns nil for unknown keys" do
      expect(described_class.stage_config(:unknown)).to be_nil
    end
  end

  describe "#last_run" do
    let(:pipeline) { create(:rag_flow) }

    it "returns the most recent run" do
      create(:rag_run, rag_flow: pipeline, created_at: 1.hour.ago)
      new_run = create(:rag_run, rag_flow: pipeline, created_at: Time.current)

      expect(pipeline.last_run).to eq(new_run)
    end
  end

  describe "amoeba deep clone" do
    let(:flow) { create(:rag_flow, :with_steps) }

    let(:clone) do
      c = flow.amoeba_dup
      c.save!
      c
    end

    it "clones all 4 stage steps" do
      expect(clone.rag_steps.count).to eq(4)
      expect(clone.source_step).to be_present
      expect(clone.chunking_step).to be_present
      expect(clone.embedding_step).to be_present
      expect(clone.storage_step).to be_present
    end

    it "excludes runs and clones step configuration" do
      create(:rag_run, rag_flow: flow)
      expect(clone.rag_runs.count).to eq(0)
      expect(clone.source_step.configuration).to eq(flow.source_step.configuration)
      expect(clone.source_step.id).not_to eq(flow.source_step.id)
    end
  end

  describe "friendly_id" do
    it "generates a slug from the name" do
      pipeline = create(:rag_flow, name: "My Pipeline")
      expect(pipeline.slug).to eq("my-pipeline")
    end

    it "regenerates the slug when the name changes" do
      pipeline = create(:rag_flow, name: "Original Name")
      pipeline.update!(name: "New Name")
      expect(pipeline.slug).to eq("new-name")
    end
  end
end
