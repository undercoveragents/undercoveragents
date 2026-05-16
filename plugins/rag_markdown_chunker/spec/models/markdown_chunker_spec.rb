# frozen_string_literal: true

require "rails_helper"

RSpec.describe RagSteps::MarkdownChunker do
  describe "validations" do
    subject { build(:rag_steps_markdown_chunker) }

    it { is_expected.to validate_presence_of(:chunk_size) }
    it { is_expected.to validate_presence_of(:chunk_overlap) }

    describe "overlap_must_be_less_than_size" do
      it "is invalid when overlap >= size" do
        chunker = build(:rag_steps_markdown_chunker, chunk_size: 100, chunk_overlap: 100)
        expect(chunker).not_to be_valid
      end

      it "is valid when overlap < size" do
        chunker = build(:rag_steps_markdown_chunker, chunk_size: 500, chunk_overlap: 100)
        expect(chunker).to be_valid
      end

      it "skips validation when chunk_overlap is blank" do
        chunker = build(:rag_steps_markdown_chunker, chunk_size: 100, chunk_overlap: nil)
        chunker.valid?
        expect(chunker.errors[:chunk_overlap]).not_to include("must be less than chunk size")
      end

      it "skips validation when chunk_size is blank" do
        chunker = build(:rag_steps_markdown_chunker, chunk_size: nil, chunk_overlap: 50)
        chunker.valid?
        expect(chunker.errors[:chunk_overlap]).not_to include("must be less than chunk size")
      end
    end
  end

  describe ".key" do
    it { expect(described_class.key).to eq("markdown_chunker") }
  end

  describe ".stage" do
    it { expect(described_class.stage).to eq(:chunking) }
  end

  describe "#chunking_strategy" do
    it { expect(described_class.new.chunking_strategy).to eq("markdown_header") }
  end

  describe ".permitted_params" do
    it "returns markdown_chunker params" do
      params = ActionController::Parameters.new(
        markdown_chunker: { chunk_size: "700", chunk_overlap: "80" },
      )
      result = described_class.permitted_params(params)
      expect(result[:chunk_size]).to eq("700")
    end
  end

  describe ".build_from_params" do
    it "returns a new instance with permitted params" do
      params = ActionController::Parameters.new(
        markdown_chunker: { chunk_size: "700", chunk_overlap: "80" },
      )
      instance = described_class.build_from_params(params)
      expect(instance).to be_a(described_class)
    end
  end

  describe "#execute" do
    it "delegates to ChunkerExecutor" do
      chunker = build(:rag_steps_markdown_chunker)
      docs = [Rag::Document.new(id: "1", content: "# Heading\n\nBody text.", metadata: {}, chunks: [])]
      result = chunker.execute(docs, {})
      expect(result).to be_an(Array)
    end
  end

  describe "#validate_configuration!" do
    it "raises when chunk_size is nil" do
      chunker = build(:rag_steps_markdown_chunker, chunk_size: nil)
      expect { chunker.validate_configuration! }.to raise_error("Chunk size must be positive")
    end

    it "does not raise when chunk_size is valid" do
      chunker = build(:rag_steps_markdown_chunker, chunk_size: 600)
      expect { chunker.validate_configuration! }.not_to raise_error
    end
  end

  describe ".label" do
    it { expect(described_class.label).to eq("Markdown") }
  end

  describe ".icon" do
    it { expect(described_class.icon).to eq("fa-brands fa-markdown") }
  end

  describe ".description" do
    it "returns a non-empty description" do
      expect(described_class.description).to include("Markdown headings")
    end
  end

  describe "#form_partial_path" do
    it "returns the expected partial path" do
      chunker = build(:rag_steps_markdown_chunker)
      expect(File.directory?(chunker.form_partial_path)).to be(true)
      expect(File.exist?(File.join(chunker.form_partial_path, "_form.html.haml"))).to be(true)
    end
  end

  describe "#to_configuration" do
    it "returns a serializable hash" do
      chunker = build(:rag_steps_markdown_chunker, chunk_size: 600, chunk_overlap: 80)
      config = chunker.to_configuration
      expect(config).to include("chunk_size" => 600, "chunk_overlap" => 80)
    end
  end

  describe "#summary" do
    it "includes chunk_size and chunk_overlap" do
      chunker = build(:rag_steps_markdown_chunker, chunk_size: 600, chunk_overlap: 80)
      expect(chunker.summary).to eq("Markdown — 600 chars, 80 overlap")
    end
  end
end
