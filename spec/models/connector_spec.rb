# frozen_string_literal: true

# == Schema Information
#
# Table name: connectors
# Database name: primary
#
#  id             :bigint           not null, primary key
#  configuration  :jsonb            not null
#  connector_type :string           not null
#  description    :text
#  enabled        :boolean          default(TRUE), not null
#  name           :string           not null
#  slug           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  tenant_id      :bigint           not null
#
# Indexes
#
#  index_connectors_on_connector_type      (connector_type)
#  index_connectors_on_enabled             (enabled)
#  index_connectors_on_slug                (slug) UNIQUE
#  index_connectors_on_tenant_id           (tenant_id)
#  index_connectors_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id)
#
require "rails_helper"

RSpec.describe Connector do
  describe "typed connector behavior" do
    it "builds SQL connectors with proper connector_type" do
      connector = build(:connector, :sql_database)
      expect(connector.connector_type).to eq("sql_database")
      expect(connector).to respond_to(:effective_port)
    end

    it "builds LLM connectors with proper connector_type" do
      connector = build(:connector, :llm_provider)
      expect(connector.connector_type).to eq("llm_provider")
      expect(connector.provider_label).to be_present
    end

    it "raises NoMethodError for unknown methods" do
      connector = build(:connector, :sql_database)
      expect { connector.non_existent_connector_method! }.to raise_error(NoMethodError)
    end

    it "responds only to methods supported by the concrete connector class" do
      connector = build(:connector, :llm_provider)
      expect(connector.respond_to?(:provider_label)).to be(true)
      expect(connector.respond_to?(:totally_unknown_method)).to be(false)
    end

    it "normalizes invalid configuration payloads before validation" do
      connector = build(:connector, :sql_database)
      connector.configuration = "invalid"
      connector.validate

      expect(connector.configuration).to eq({})
    end

    it "keeps hash configuration untouched during validation normalization" do
      connector = build(:connector, :sql_database)
      connector.configuration = { "adapter_type" => "postgresql" }

      expect { connector.validate }.not_to(change { connector.configuration })
    end
  end

  describe "validations" do
    subject { build(:connector, :sql_database) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:tenant_id).case_insensitive }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_length_of(:description).is_at_most(500) }
  end

  describe ".sensitive_keys_for_hash" do
    it "returns sensitive key symbols across all connector types" do
      keys = described_class.sensitive_keys_for_hash({})
      expect(keys).to be_an(Array)
    end

    it "skips connector types whose class does not respond to sensitive_keys" do
      allow(ConnectorPlugin).to receive(:type_keys).and_return(["sql_database", "fake_no_keys"])
      no_key_class = Class.new
      allow(ConnectorPlugin).to receive(:resolve).with("sql_database").and_call_original
      allow(ConnectorPlugin).to receive(:resolve).with("fake_no_keys").and_return(no_key_class)
      described_class.reset_sensitive_keys_cache!
      keys = described_class.sensitive_keys_for_hash({})
      expect(keys).to be_an(Array)
      described_class.reset_sensitive_keys_cache!
    end

    it "skips connector types that raise NameError during resolution" do
      allow(ConnectorPlugin).to receive(:type_keys).and_return(["missing_connector"])
      allow(ConnectorPlugin).to receive(:resolve).with("missing_connector").and_raise(NameError, "Missing")
      described_class.reset_sensitive_keys_cache!

      expect(described_class.sensitive_keys_for_hash({})).to eq([])
    ensure
      described_class.reset_sensitive_keys_cache!
    end

    it "returns an empty list when the registry lookup fails" do
      allow(ConnectorPlugin).to receive(:type_keys).and_raise(StandardError, "registry unavailable")
      described_class.reset_sensitive_keys_cache!

      expect(described_class.sensitive_keys_for_hash({})).to eq([])
    ensure
      described_class.reset_sensitive_keys_cache!
    end
  end

  describe ".reset_sensitive_keys_cache!" do
    it "clears the cached sensitive keys so they are recomputed on next call" do
      described_class.sensitive_keys_for_hash({}) # populate cache
      described_class.reset_sensitive_keys_cache!
      # The cache should be nil now; calling sensitive_keys_for_hash recomputes
      expect(described_class.sensitive_keys_for_hash({})).to be_an(Array)
    end
  end

  describe "validation — connector_type_registered" do
    it "adds an error when the connector_type is not a registered plugin type" do
      connector = build(:connector, :sql_database)
      connector.connector_type = "nonexistent_connector_type_xyz"
      expect(connector).not_to be_valid
      expect(connector.errors[:connector_type]).to include("is not a registered connector type")
    end

    it "skips validation when connector_type is blank" do
      connector = described_class.new(connector_type: "", name: "Test", enabled: true)
      connector.valid?
      expect(connector.errors[:connector_type]).not_to include("is not a registered connector type")
    end
  end

  describe "#validate_configurator with nil configurator" do
    it "skips validation when no configurator is resolved" do
      connector = described_class.new(connector_type: "nonexistent_xyz", name: "X", enabled: true)
      allow(connector).to receive(:configurator).and_return(nil)
      connector.valid?
      expect(connector.errors[:base]).to be_empty
    end
  end

  describe "#apply_configurator_before_save" do
    it "skips configuration update when configurator is nil" do
      connector = build(:connector, :sql_database)
      allow(connector).to receive(:configurator).and_return(nil)
      original = connector.configuration.dup
      connector.send(:apply_configurator_before_save)
      expect(connector.configuration).to eq(original)
    end
  end

  describe "#ensure_configuration" do
    it "resets configuration to an empty hash when value is not a Hash" do
      connector = described_class.new
      allow(connector).to receive(:configuration).and_return("not-a-hash")
      allow(connector).to receive(:configuration=)
      connector.send(:ensure_configuration)
      expect(connector).to have_received(:configuration=).with({})
    end
  end

  describe "#notify_configurator_of_changes" do
    it "skips on_configuration_change when configuration has not changed" do
      connector = create(:connector, :sql_database)
      configurator = instance_double(Connectors::SqlDatabase)
      allow(configurator).to receive(:on_configuration_change)
      allow(configurator).to receive(:respond_to?).with(:on_configuration_change).and_return(true)
      allow(connector).to receive_messages(configurator:, will_save_change_to_configuration?: false)

      connector.send(:notify_configurator_of_changes)

      expect(configurator).not_to have_received(:on_configuration_change)
    end
  end

  describe "#configurator caching" do
    it "returns the same cached configurator on repeated access" do
      connector = build(:connector, :sql_database)
      first = connector.configurator
      second = connector.configurator
      expect(first).to equal(second)
    end

    it "rebuilds the configurator when connector_type changes" do
      connector = create(:connector, :sql_database)
      first = connector.configurator
      connector.connector_type = "llm_provider"
      second = connector.configurator
      expect(second).not_to equal(first)
    end
  end

  describe "#configuration= clears cached configurator" do
    it "rebuilds configurator after configuration is reassigned" do
      connector = create(:connector, :sql_database)
      first = connector.configurator
      connector.configuration = { "adapter_type" => "mysql2" }
      second = connector.configurator
      expect(second).not_to equal(first)
    end
  end

  describe "#reload clears cached configurator" do
    it "rebuilds configurator after reload" do
      connector = create(:connector, :sql_database)
      first = connector.configurator
      connector.reload
      second = connector.configurator
      expect(second).not_to equal(first)
    end
  end

  describe "#type_label" do
    it "returns the registered label for the connector type" do
      connector = build(:connector, :sql_database)
      expect(connector.type_label).to eq("SQL Database")
    end

    it "falls back to titleized connector_type when label_for returns nil" do
      connector = build(:connector, :sql_database)
      allow(ConnectorPlugin).to receive(:label_for).and_return(nil)
      expect(connector.type_label).to eq("Sql Database")
    end
  end

  describe "#type_icon" do
    it "returns the registered icon for the connector type" do
      connector = build(:connector, :sql_database)
      expect(connector.type_icon).to be_a(String)
    end

    it "falls back to default icon when icon_for returns nil" do
      connector = build(:connector, :sql_database)
      allow(ConnectorPlugin).to receive(:icon_for).and_return(nil)
      expect(connector.type_icon).to eq("fa-solid fa-plug")
    end
  end

  describe "#notify_configurator_of_changes edge case" do
    it "skips when configurator does not respond to on_configuration_change" do
      connector = create(:connector, :llm_provider, :enabled)
      connector.description = "updated"
      expect { connector.save! }.not_to raise_error
    end
  end

  describe "scopes" do
    let!(:sql_connector) { create(:connector, :sql_database, enabled: true) }
    let!(:disabled_connector) { create(:connector, :mcp_server, enabled: false) }

    describe ".enabled" do
      it "returns only enabled connectors" do
        expect(described_class.enabled).to contain_exactly(sql_connector)
      end
    end

    describe ".disabled" do
      it "returns only disabled connectors" do
        expect(described_class.disabled).to contain_exactly(disabled_connector)
      end
    end

    describe ".sql_databases" do
      it "returns only SQL database connectors" do
        expect(described_class.sql_databases).to contain_exactly(sql_connector)
      end
    end

    describe ".authentications" do
      it "returns only authentication connectors" do
        auth_connector = create(:connector, :authentication, enabled: true)
        expect(described_class.authentications).to contain_exactly(auth_connector)
      end
    end

    describe ".ordered" do
      it "returns connectors ordered by name" do
        expect(described_class.ordered).to eq(described_class.order(:name))
      end
    end
  end
end
