# frozen_string_literal: true

require "rails_helper"

RSpec.describe RagSteps::FixedSizeChunker do
  describe "validations" do
    subject(:chunker) { build(:rag_steps_fixed_size_chunker) }

    it { is_expected.to validate_presence_of(:chunk_size) }
    it { is_expected.to validate_presence_of(:chunk_overlap) }

    it "validates chunk_size is greater than 0" do
      chunker.chunk_size = 0
      chunker.valid?
      expect(chunker.errors[:chunk_size]).to include("must be greater than 0")
    end

    it "validates chunk_overlap is not negative" do
      chunker.chunk_overlap = -1
      chunker.valid?
      expect(chunker.errors[:chunk_overlap]).to include("must be greater than or equal to 0")
    end

    describe "overlap_must_be_less_than_size" do
      it "is invalid when overlap >= size" do
        chunker = build(:rag_steps_fixed_size_chunker, chunk_size: 100, chunk_overlap: 100)
        expect(chunker).not_to be_valid
        expect(chunker.errors[:chunk_overlap]).to be_present
      end

      it "is valid when overlap < size" do
        chunker = build(:rag_steps_fixed_size_chunker, chunk_size: 1000, chunk_overlap: 200)
        expect(chunker).to be_valid
      end

      it "skips validation when chunk_overlap is blank" do
        chunker = build(:rag_steps_fixed_size_chunker, chunk_size: 100, chunk_overlap: nil)
        chunker.valid?
        expect(chunker.errors[:chunk_overlap]).not_to include("must be less than chunk size")
      end

      it "skips validation when chunk_size is blank" do
        chunker = build(:rag_steps_fixed_size_chunker, chunk_size: nil, chunk_overlap: 50)
        chunker.valid?
        expect(chunker.errors[:chunk_overlap]).not_to include("must be less than chunk size")
      end
    end
  end

  describe ".key" do
    it { expect(described_class.key).to eq("fixed_size_chunker") }
  end

  describe ".stage" do
    it { expect(described_class.stage).to eq(:chunking) }
  end

  describe "#chunking_strategy" do
    it { expect(described_class.new.chunking_strategy).to eq("fixed_size") }
  end

  describe "#validate_configuration!" do
    it "raises when chunk_size is not positive" do
      chunker = build(:rag_steps_fixed_size_chunker, chunk_size: nil)
      expect { chunker.validate_configuration! }.to raise_error("Chunk size must be positive")
    end

    it "does not raise when valid" do
      chunker = build(:rag_steps_fixed_size_chunker)
      expect { chunker.validate_configuration! }.not_to raise_error
    end
  end

  describe "#summary" do
    it "includes chunk_size and chunk_overlap" do
      chunker = build(:rag_steps_fixed_size_chunker, chunk_size: 500, chunk_overlap: 100)
      expect(chunker.summary).to eq("Fixed Size — 500 chars, 100 overlap")
    end
  end

  describe ".label" do
    it { expect(described_class.label).to eq("Fixed Size") }
  end

  describe ".icon" do
    it { expect(described_class.icon).to eq("fa-solid fa-ruler") }
  end

  describe ".description" do
    it "returns a non-empty description" do
      expect(described_class.description).to include("fixed-size chunks")
    end
  end

  describe ".permitted_params" do
    it "returns fixed_size_chunker params" do
      params = ActionController::Parameters.new(
        fixed_size_chunker: { chunk_size: "500", chunk_overlap: "50", separator: "," },
      )
      result = described_class.permitted_params(params)
      expect(result[:chunk_size]).to eq("500")
      expect(result[:separator]).to eq(",")
    end
  end

  describe ".build_from_params" do
    it "returns a new instance with permitted params" do
      params = ActionController::Parameters.new(
        fixed_size_chunker: { chunk_size: "500", chunk_overlap: "50" },
      )
      instance = described_class.build_from_params(params)
      expect(instance).to be_a(described_class)
      expect(instance.chunk_size).to eq(500)
    end
  end

  describe "#form_partial_path" do
    it "returns the expected partial path" do
      chunker = build(:rag_steps_fixed_size_chunker)
      expect(File.directory?(chunker.form_partial_path)).to be(true)
      expect(File.exist?(File.join(chunker.form_partial_path, "_form.html.haml"))).to be(true)
    end
  end

  describe "#to_configuration" do
    it "returns a serializable hash" do
      chunker = build(:rag_steps_fixed_size_chunker, chunk_size: 500, chunk_overlap: 50)
      config = chunker.to_configuration
      expect(config).to include("chunk_size" => 500, "chunk_overlap" => 50)
    end
  end

  describe "#execute" do
    it "delegates to ChunkerExecutor" do
      chunker = build(:rag_steps_fixed_size_chunker)
      allow(Rag::Steps::ChunkerExecutor).to receive(:new).and_call_original
      allow_any_instance_of(Rag::Steps::ChunkerExecutor).to receive(:call).and_return([]) # rubocop:disable RSpec/AnyInstance
      chunker.execute([], {})
      expect(Rag::Steps::ChunkerExecutor).to have_received(:new).with(chunker, {})
    end
  end
end
