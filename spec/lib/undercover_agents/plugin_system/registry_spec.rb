# frozen_string_literal: true

require "rails_helper"

RSpec.describe UndercoverAgents::PluginSystem::Registry do
  subject(:registry) { described_class.new }

  let(:definition) do
    UndercoverAgents::PluginSystem::Definition.new("test_registry_plugin").tap do |d|
      d.name = "Test Plugin"
      d.category = [:rag_chunking]
      d.add_rag_chunker("RagSteps::FixedSizeChunker")
      d.freeze!
    end
  end

  describe "#register and #find" do
    it "registers and finds a definition" do
      registry.register(definition)
      expect(registry.find("test_registry_plugin")).to eq(definition)
    end

    it "returns nil for unknown identifier" do
      expect(registry.find("unknown")).to be_nil
    end
  end

  describe "#all" do
    it "returns all registered definitions" do
      registry.register(definition)
      expect(registry.all).to include(definition)
    end
  end

  describe "#by_category" do
    it "filters definitions by category" do
      registry.register(definition)
      expect(registry.by_category(:rag_chunking)).to include(definition)
      expect(registry.by_category(:other)).to be_empty
    end
  end

  describe "#enabled and #disabled" do
    before { registry.register(definition) }

    it "returns enabled plugins (default is enabled)" do
      expect(registry.enabled).to include(definition)
      expect(registry.disabled).to be_empty
    end

    it "returns disabled plugins when set_enabled is false" do
      registry.set_enabled("test_registry_plugin", false)
      expect(registry.disabled).to include(definition)
      expect(registry.enabled).to be_empty
    end
  end

  describe "#enabled?" do
    it "defaults to true for unregistered state" do
      expect(registry.enabled?("anything")).to be(true)
    end

    it "returns false after set_enabled(false)" do
      registry.set_enabled("foo", false)
      expect(registry.enabled?("foo")).to be(false)
    end
  end

  describe "#count and #empty?" do
    it "returns 0 when empty" do
      expect(registry.count).to eq(0)
      expect(registry.empty?).to be(true)
    end

    it "returns count after registration" do
      registry.register(definition)
      expect(registry.count).to eq(1)
      expect(registry.empty?).to be(false)
    end
  end

  describe "#clear_definitions!" do
    it "removes all registered definitions" do
      registry.register(definition)

      registry.clear_definitions!

      expect(registry.count).to eq(0)
      expect(registry).to be_empty
    end
  end

  describe "#sync_with_database!" do
    before { registry.register(definition) }

    it "creates Plugin records for new definitions" do
      expect { registry.sync_with_database! }.to change(Plugin, :count).by(1)
    end

    it "ignores duplicate identifier validation errors from stale existence checks" do
      plugin = Plugin.create!(identifier: "test_registry_plugin", enabled: true, metadata: {})
      allow(Plugin).to receive(:where).with(identifier: ["test_registry_plugin"]).and_return([], [plugin])

      expect { registry.sync_with_database! }.not_to raise_error
    end

    it "re-raises non-duplicate validation errors while creating missing plugins" do
      invalid_plugin = Plugin.new(identifier: nil, enabled: true, metadata: {})
      allow(Plugin).to receive(:new).and_return(invalid_plugin)

      expect { registry.sync_with_database! }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "updates metadata on existing Plugin records" do
      Plugin.create!(identifier: "test_registry_plugin", enabled: true, metadata: { "name" => "Old Name" })
      registry.sync_with_database!
      expect(Plugin.find_by(identifier: "test_registry_plugin").metadata["name"]).to eq("Test Plugin")
    end

    it "does not update metadata when the stored metadata already matches" do
      persisted_metadata = JSON.parse(definition.to_h.except(:root_path).to_json)

      plugin = Plugin.create!(
        identifier: "test_registry_plugin",
        enabled: true,
        metadata: persisted_metadata,
      )
      allow(plugin).to receive(:update!).and_call_original
      allow(Plugin).to receive(:where).with(identifier: ["test_registry_plugin"]).and_return([plugin])

      registry.sync_with_database!

      expect(plugin).not_to have_received(:update!)
    end

    it "reads enabled state from existing Plugin records" do
      Plugin.create!(identifier: "test_registry_plugin", enabled: false, metadata: {})
      registry.sync_with_database!
      expect(registry.enabled?("test_registry_plugin")).to be(false)
    end

    it "skips metadata update for Plugin records not in the registry" do
      orphan = Plugin.create!(identifier: "orphaned_plugin_xyz", enabled: true, metadata: { "name" => "Orphan" })
      registry.sync_with_database!
      orphan.reload
      expect(orphan.metadata["name"]).to eq("Orphan")
    end
  end
end
