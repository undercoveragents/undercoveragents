# frozen_string_literal: true

# == Schema Information
#
# Table name: rag_steps
# Database name: primary
#
#  id            :bigint           not null, primary key
#  configuration :jsonb            not null
#  module_type   :string           not null
#  stage         :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  rag_flow_id   :bigint           not null
#
# Indexes
#
#  idx_rag_steps_flow_stage        (rag_flow_id,stage) UNIQUE
#  index_rag_steps_on_rag_flow_id  (rag_flow_id)
#
# Foreign Keys
#
#  fk_rails_...  (rag_flow_id => rag_flows.id)
#
require "rails_helper"

RSpec.describe RagStep do
  let(:flow) { create(:rag_flow) }

  describe "validations" do
    subject do
      described_class.new(
        rag_flow: flow,
        stage: "chunking",
        module_type: "fixed_size_chunker",
        configuration: { chunk_size: 1000, chunk_overlap: 200 },
      )
    end

    it { is_expected.to validate_presence_of(:stage) }
    it { is_expected.to validate_inclusion_of(:stage).in_array(described_class::STAGES) }
    it { is_expected.to validate_presence_of(:module_type) }
  end

  describe "associations" do
    subject do
      described_class.new(
        rag_flow: flow,
        stage: "chunking",
        module_type: "fixed_size_chunker",
        configuration: { chunk_size: 1000, chunk_overlap: 200 },
      )
    end

    it { is_expected.to belong_to(:rag_flow) }
  end

  describe "#configurator" do
    it "returns the correct configurator class for the module_type" do
      step = create(:rag_step,
                    rag_flow: flow,
                    stage: "chunking",
                    module_type: "fixed_size_chunker",
                    configuration: { "chunk_size" => 500, "chunk_overlap" => 100 },)
      configurator = step.configurator
      expect(configurator).to be_a(RagSteps::FixedSizeChunker)
      expect(configurator.chunk_size).to eq(500)
    end

    it "raises for unknown module_type" do
      step = build(:rag_step,
                   rag_flow: flow,
                   stage: "chunking",
                   module_type: "nonexistent_module",
                   configuration: {},)
      expect { step.configurator }.to raise_error(RuntimeError, /Unknown module type/)
    end

    it "returns the cached configurator when nothing has changed" do
      step = create(:rag_step,
                    rag_flow: flow,
                    stage: "chunking",
                    module_type: "fixed_size_chunker",
                    configuration: { "chunk_size" => 500, "chunk_overlap" => 100 },)
      first = step.configurator
      second = step.configurator
      expect(first).to equal(second)
    end

    it "rebuilds configurator when module_type changes" do
      step = create(:rag_step,
                    rag_flow: flow,
                    stage: "chunking",
                    module_type: "fixed_size_chunker",
                    configuration: { "chunk_size" => 500, "chunk_overlap" => 100 },)
      first = step.configurator
      step.module_type = "paragraph_chunker"
      second = step.configurator
      expect(second).not_to equal(first)
    end

    it "rebuilds configurator when configuration changes" do
      step = create(:rag_step,
                    rag_flow: flow,
                    stage: "chunking",
                    module_type: "fixed_size_chunker",
                    configuration: { "chunk_size" => 500, "chunk_overlap" => 100 },)
      first = step.configurator
      step.configuration = { "chunk_size" => 1000, "chunk_overlap" => 200 }
      second = step.configurator
      expect(second).not_to equal(first)
    end

    it "builds configurators that do not expose _rag_step_record=" do
      stub_const("RagStepWithoutRecord", Class.new do
        def initialize(*) = nil
      end,)
      allow(RagStepPlugin).to receive(:resolve).and_call_original
      allow(RagStepPlugin).to receive(:resolve).with("no_record_step").and_return(RagStepWithoutRecord)

      step = build(:rag_step, rag_flow: flow, stage: "chunking", module_type: "no_record_step", configuration: {})

      expect(step.send(:build_configurator)).to be_a(RagStepWithoutRecord)
    end
  end

  describe "#type_label" do
    it "returns the type label from the configurator" do
      step = create(:rag_step,
                    rag_flow: flow,
                    stage: "chunking",
                    module_type: "fixed_size_chunker",
                    configuration: { "chunk_size" => 500, "chunk_overlap" => 100 },)
      expect(step.type_label).to eq("Fixed Size")
    end

    it "returns Unknown module for bad module_type" do
      step = build(:rag_step,
                   rag_flow: flow,
                   stage: "chunking",
                   module_type: "nonexistent_module",
                   configuration: {},)
      expect(step.type_label).to eq("Unknown module")
    end

    it "re-raises non-module RuntimeErrors" do
      step = create(:rag_step,
                    rag_flow: flow,
                    stage: "chunking",
                    module_type: "fixed_size_chunker",
                    configuration: { "chunk_size" => 500, "chunk_overlap" => 100 },)
      allow(step.configurator).to receive(:label).and_raise(RuntimeError, "unexpected error")
      expect { step.type_label }.to raise_error(RuntimeError, "unexpected error")
    end
  end

  describe "#summary" do
    it "returns the summary from the configurator" do
      step = create(:rag_step,
                    rag_flow: flow,
                    stage: "chunking",
                    module_type: "fixed_size_chunker",
                    configuration: { "chunk_size" => 500, "chunk_overlap" => 100 },)
      expect(step.summary).to eq("Fixed Size — 500 chars, 100 overlap")
    end

    it "returns humanized module_type for bad module_type" do
      step = build(:rag_step,
                   rag_flow: flow,
                   stage: "chunking",
                   module_type: "nonexistent_module",
                   configuration: {},)
      expect(step.summary).to eq("Nonexistent module")
    end

    it "re-raises non-module RuntimeErrors" do
      step = create(:rag_step,
                    rag_flow: flow,
                    stage: "chunking",
                    module_type: "fixed_size_chunker",
                    configuration: { "chunk_size" => 500, "chunk_overlap" => 100 },)
      allow(step.configurator).to receive(:summary).and_raise(RuntimeError, "unexpected error")
      expect { step.summary }.to raise_error(RuntimeError, "unexpected error")
    end
  end

  describe "delegation" do
    let(:step) do
      create(:rag_step,
             rag_flow: flow,
             stage: "chunking",
             module_type: "fixed_size_chunker",
             configuration: { "chunk_size" => 500, "chunk_overlap" => 100 },)
    end

    it "delegates validate_configuration! to configurator" do
      expect { step.validate_configuration! }.not_to raise_error
    end
  end

  describe ".ordered" do
    it "orders by stage natural order" do
      source_step = create(:rag_step, rag_flow: flow, stage: "source",
                                      module_type: "sql_database_source",
                                      configuration: { "query" => "SELECT 1", "content_column" => "c",
                                                       "batch_size" => 100, },)
      chunking_step = create(:rag_step, rag_flow: flow, stage: "chunking",
                                        module_type: "fixed_size_chunker",
                                        configuration: { "chunk_size" => 500, "chunk_overlap" => 100 },)
      ordered = flow.rag_steps.ordered
      expect(ordered.first).to eq(source_step)
      expect(ordered.last).to eq(chunking_step)
    end
  end
end
