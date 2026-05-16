# frozen_string_literal: true

require "rails_helper"

RSpec.describe RagStepPlugin do
  # Use a concrete subclass for instance-method testing
  let(:instance) { RagSteps::FixedSizeChunker.new }

  describe ".register" do
    after do
      # Remove only test-prefixed entries from the internal maps, preserving
      # plugin registrations that may have been lazily autoloaded.
      type_map = described_class.instance_variable_get(:@type_map)
      stage_map = described_class.instance_variable_get(:@stage_map)
      type_map.delete_if { |k, _| k.start_with?("test_") }
      stage_map.delete_if { |k, _| k.start_with?("test_") }
    end

    it "raises for an invalid stage" do
      expect do
        described_class.register(
          "test_invalid_stage",
          "RagSteps::FixedSizeChunker",
          label: "Fixed Size",
          icon: "fa-solid fa-ruler",
          stage: :invalid,
        )
      end.to raise_error(ArgumentError, /Stage 'invalid' is invalid/)
    end

    it "is idempotent for the same key, class, and stage" do
      described_class.register(
        "test_idempotent",
        "RagSteps::FixedSizeChunker",
        label: "Fixed Size",
        icon: "fa-solid fa-ruler",
        stage: :chunking,
      )

      expect do
        described_class.register(
          "test_idempotent",
          "RagSteps::FixedSizeChunker",
          label: "Fixed Size",
          icon: "fa-solid fa-ruler",
          stage: :chunking,
        )
      end.not_to raise_error
    end

    it "raises for a duplicate key with different class" do
      described_class.register(
        "test_duplicate_key",
        "RagSteps::FixedSizeChunker",
        label: "Fixed Size",
        icon: "fa-solid fa-ruler",
        stage: :chunking,
      )

      expect do
        described_class.register(
          "test_duplicate_key",
          "RagSteps::ParagraphChunker",
          label: "Paragraph",
          icon: "fa-solid fa-paragraph",
          stage: :chunking,
        )
      end.to raise_error(ArgumentError, /already registered/)
    end
  end

  describe "VALID_STAGES" do
    it "contains all four stages" do
      expect(described_class::VALID_STAGES).to eq([:source, :chunking, :embedding, :storage])
    end
  end

  describe "Result" do
    it "creates a result with success and message" do
      result = described_class::Result.new(success?: true, message: "ok")
      expect(result.success?).to be(true)
      expect(result.message).to eq("ok")
    end
  end

  describe ".type_map" do
    it "returns a defensive copy" do
      map = described_class.type_map
      map["injected"] = "Bad"
      expect(described_class.type_map).not_to have_key("injected")
    end
  end

  describe ".stage_map" do
    it "returns a defensive copy" do
      map = described_class.stage_map
      map["injected"] = :source
      expect(described_class.stage_map).not_to have_key("injected")
    end
  end

  describe ".resolve" do
    it "returns the class for a known type key" do
      expect(described_class.resolve("sql_database_source")).to eq(RagSteps::SqlDatabaseSource)
    end

    it "returns nil for an unknown key" do
      expect(described_class.resolve("unknown")).to be_nil
    end
  end

  describe ".stage_for" do
    it "returns the stage for a known type key" do
      expect(described_class.stage_for("fixed_size_chunker")).to eq(:chunking)
    end

    it "returns nil for an unknown key" do
      expect(described_class.stage_for("nonexistent_step_xyz")).to be_nil
    end
  end

  describe ".modules_for_stage" do
    before { UndercoverAgents::PluginSystem.register_step_types! }

    it "returns descriptors for each module in the stage" do
      modules = described_class.modules_for_stage(:chunking)
      expect(modules).to be_an(Array)
      expect(modules).not_to be_empty
      expect(modules).to all(include(:key, :label, :icon, :description))
    end

    it "excludes disabled plugins" do
      registry = UndercoverAgents::PluginSystem.registry
      allow(registry).to receive(:enabled?).and_call_original
      allow(registry).to receive(:enabled?).with("fixed_size_chunker").and_return(false)

      modules = described_class.modules_for_stage(:chunking)
      expect(modules.pluck(:key)).not_to include("fixed_size_chunker")
    end
  end

  describe ".type_keys" do
    it "returns all registered type keys" do
      keys = described_class.type_keys
      expect(keys).to include("sql_database_source", "fixed_size_chunker", "llm_embedder")
    end
  end

  describe "#execute (default)" do
    it "raises NotImplementedError by default" do
      # Create a minimal test class that includes RagStepPlugin but doesn't override #execute
      stub_class = Class.new do
        include ActiveModel::Model
        include ActiveModel::Attributes
        include RagStepPlugin

        def self.key = "test_stub"
        def self.label = "Test Stub"
        def self.icon = "fa-solid fa-puzzle-piece"
      end
      expect { stub_class.new.execute([], {}) }.to raise_error(NotImplementedError)
    end
  end

  describe "#each_batch (default)" do
    it "yields result of execute([]) as a single batch" do
      chunker = build(:rag_steps_fixed_size_chunker, chunk_size: 1000, chunk_overlap: 0)
      # Chunkers don't override #each_batch, so the RagStepPlugin default is used
      batches = []
      chunker.each_batch({}) { |b| batches << b }
      expect(batches.length).to eq(1)
    end
  end

  describe "#validate_configuration! (default)" do
    it "does not raise by default (no-op)" do
      stub_class = Class.new do
        include ActiveModel::Model
        include ActiveModel::Attributes
        include RagStepPlugin

        def self.key = "test_stub"
        def self.label = "Test Stub"
        def self.icon = "fa-solid fa-puzzle-piece"
      end
      expect { stub_class.new.validate_configuration! }.not_to raise_error
    end
  end

  describe "#form_partial_path (default)" do
    it "returns an absolute path to a views directory containing _form.html.haml" do
      chunker = RagSteps::FixedSizeChunker.new
      expect(File.directory?(chunker.form_partial_path)).to be(true)
      expect(File.exist?(File.join(chunker.form_partial_path, "_form.html.haml"))).to be(true)
    end
  end

  describe "#summary (default)" do
    it "returns the class label for a module that does not override summary" do
      stub_class = Class.new do
        include RagStepPlugin

        key "stub_rag_summary_test"
        label "Stub Step"
        icon "fa-solid fa-circle"
        stage :chunking
      end

      expect(stub_class.new.summary).to eq("Stub Step")
    end
  end

  describe ".reset!" do
    it "clears all registered step types" do
      described_class.reset!
      expect(described_class.type_map).to be_empty
    ensure
      UndercoverAgents::PluginSystem.register_step_types!
    end
  end
end
