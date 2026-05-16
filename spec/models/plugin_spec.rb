# frozen_string_literal: true

# == Schema Information
#
# Table name: plugins
# Database name: primary
#
#  id         :bigint           not null, primary key
#  enabled    :boolean          default(TRUE), not null
#  identifier :string           not null
#  metadata   :jsonb            not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_plugins_on_identifier  (identifier) UNIQUE
#
require "rails_helper"

RSpec.describe Plugin do
  subject { build(:plugin) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:identifier) }
    it { is_expected.to validate_uniqueness_of(:identifier) }

    it "accepts true and false for enabled" do
      plugin = build(:plugin, enabled: true)
      expect(plugin).to be_valid

      plugin.enabled = false
      expect(plugin).to be_valid
    end

    it "rejects nil for enabled" do
      plugin = build(:plugin, enabled: nil)
      expect(plugin).not_to be_valid
      expect(plugin.errors[:enabled]).to be_present
    end
  end

  describe "scopes" do
    let!(:enabled_plugin) { create(:plugin) }
    let!(:disabled_plugin) { create(:plugin, :disabled) }

    it "returns only enabled plugins" do
      expect(described_class.enabled).to include(enabled_plugin)
      expect(described_class.enabled).not_to include(disabled_plugin)
    end

    it "returns only disabled plugins" do
      expect(described_class.disabled).to include(disabled_plugin)
      expect(described_class.disabled).not_to include(enabled_plugin)
    end

    it "returns ordered by identifier" do
      abc = create(:plugin, identifier: "aaa_plugin")
      xyz = create(:plugin, identifier: "zzz_plugin")
      expect(described_class.ordered.first).to eq(abc)
      expect(described_class.ordered.last).to eq(xyz)
    end
  end

  describe "#definition" do
    it "delegates to the plugin system registry" do
      plugin = create(:plugin, identifier: "fixed_size_chunker")
      expect(plugin.definition).to be_a(UndercoverAgents::PluginSystem::Definition)
    end

    it "returns nil for unregistered identifiers" do
      plugin = create(:plugin, identifier: "nonexistent_plugin_1234")
      expect(plugin.definition).to be_nil
    end
  end

  describe "#plugin_name" do
    it "returns name from metadata" do
      plugin = build(:plugin, metadata: { "name" => "My Plugin" })
      expect(plugin.plugin_name).to eq("My Plugin")
    end

    it "falls back to titleized identifier when metadata has no name" do
      plugin = build(:plugin, identifier: "my_custom", metadata: {})
      expect(plugin.plugin_name).to eq("My Custom")
    end

    it "falls back when metadata is nil" do
      plugin = build(:plugin, identifier: "my_custom")
      plugin.metadata = nil
      expect(plugin.plugin_name).to eq("My Custom")
    end
  end

  describe "#plugin_version" do
    it "returns version from metadata" do
      plugin = build(:plugin, metadata: { "version" => "2.0.0" })
      expect(plugin.plugin_version).to eq("2.0.0")
    end

    it "falls back to 0.0.0 when metadata has no version" do
      plugin = build(:plugin, metadata: {})
      expect(plugin.plugin_version).to eq("0.0.0")
    end

    it "falls back when metadata is nil" do
      plugin = build(:plugin)
      plugin.metadata = nil
      expect(plugin.plugin_version).to eq("0.0.0")
    end
  end

  describe "#plugin_author" do
    it "returns author from metadata" do
      plugin = build(:plugin, metadata: { "author" => "Alice" })
      expect(plugin.plugin_author).to eq("Alice")
    end

    it "falls back to Unknown" do
      plugin = build(:plugin, metadata: {})
      expect(plugin.plugin_author).to eq("Unknown")
    end

    it "falls back when metadata is nil" do
      plugin = build(:plugin)
      plugin.metadata = nil
      expect(plugin.plugin_author).to eq("Unknown")
    end
  end

  describe "#plugin_description" do
    it "returns description from metadata" do
      plugin = build(:plugin, metadata: { "description" => "A test plugin" })
      expect(plugin.plugin_description).to eq("A test plugin")
    end

    it "falls back to empty string" do
      plugin = build(:plugin, metadata: {})
      expect(plugin.plugin_description).to eq("")
    end

    it "falls back when metadata is nil" do
      plugin = build(:plugin)
      plugin.metadata = nil
      expect(plugin.plugin_description).to eq("")
    end
  end

  describe "#plugin_icon" do
    it "returns icon from metadata" do
      plugin = build(:plugin, metadata: { "icon" => "fa-solid fa-star" })
      expect(plugin.plugin_icon).to eq("fa-solid fa-star")
    end

    it "falls back to default puzzle piece icon" do
      plugin = build(:plugin, metadata: {})
      expect(plugin.plugin_icon).to eq("fa-solid fa-puzzle-piece")
    end

    it "falls back when metadata is nil" do
      plugin = build(:plugin)
      plugin.metadata = nil
      expect(plugin.plugin_icon).to eq("fa-solid fa-puzzle-piece")
    end
  end

  describe "#plugin_category" do
    it "returns category from metadata" do
      plugin = build(:plugin, metadata: { "category" => "rag_step" })
      expect(plugin.plugin_category).to eq("rag_step")
    end

    it "falls back to general" do
      plugin = build(:plugin, metadata: {})
      expect(plugin.plugin_category).to eq("general")
    end

    it "falls back when metadata is nil" do
      plugin = build(:plugin)
      plugin.metadata = nil
      expect(plugin.plugin_category).to eq("general")
    end
  end

  describe "#plugin_stage" do
    it "returns stage from metadata" do
      plugin = build(:plugin, metadata: { "stage" => "chunking" })
      expect(plugin.plugin_stage).to eq("chunking")
    end

    it "returns nil when no stage" do
      plugin = build(:plugin, metadata: {})
      expect(plugin.plugin_stage).to be_nil
    end

    it "returns nil when metadata is nil" do
      plugin = build(:plugin)
      plugin.metadata = nil
      expect(plugin.plugin_stage).to be_nil
    end
  end
end
