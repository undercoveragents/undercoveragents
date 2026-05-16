# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConnectorPlugin do
  # Helper to register a test connector type and clean up afterwards.
  def with_test_connector(key, klass_name, **opts)
    described_class.register(key, klass_name, label: opts.fetch(:label, "Test Label"),
                                              icon: opts.fetch(:icon, "fa-solid fa-plug"),
                                              description: opts.fetch(:description, "Test description"),)
    yield
  ensure
    described_class.reset!
    UndercoverAgents::PluginSystem.register_connector_types!
  end

  describe ".register" do
    it "raises ArgumentError when registering the same key with a different class" do
      with_test_connector("test_dup_connector", "SomeClass") do
        expect do
          described_class.register("test_dup_connector", "AnotherClass", label: "X", icon: "X")
        end.to raise_error(ArgumentError, /already registered/)
      end
    end

    it "is idempotent when registering the same key and class again" do
      with_test_connector("test_idem_connector", "SameConnectorClass") do
        expect do
          described_class.register("test_idem_connector", "SameConnectorClass", label: "L", icon: "I")
        end.not_to raise_error
      end
    end
  end

  describe ".reset!" do
    it "clears all registered connector types" do
      described_class.register("test_reset_conn", "Connectors::SqlDatabase",
                               label: "Test", icon: "fa-test",)
      described_class.reset!

      expect(described_class.type_map).to be_empty
    ensure
      UndercoverAgents::PluginSystem.register_connector_types!
    end
  end

  describe ".type_map" do
    it "returns a hash of registered type keys to class names" do
      expect(described_class.type_map).to be_a(Hash)
      expect(described_class.type_map).to include("sql_database" => "Connectors::SqlDatabase")
    end

    it "returns a duplicate (not the internal map)" do
      map = described_class.type_map
      map["injected"] = "Something"
      expect(described_class.type_map).not_to have_key("injected")
    end
  end

  describe ".label_for" do
    it "returns the label for a registered type" do
      expect(described_class.label_for("sql_database")).to eq("SQL Database")
    end

    it "returns nil for an unknown type" do
      expect(described_class.label_for("nonexistent_connector")).to be_nil
    end
  end

  describe ".icon_for" do
    it "returns the icon for a registered type" do
      expect(described_class.icon_for("sql_database")).to be_a(String)
    end

    it "returns nil for an unknown type" do
      expect(described_class.icon_for("nonexistent_connector")).to be_nil
    end
  end

  describe ".all_types" do
    it "returns type metadata including key, label, icon, and description" do
      types = described_class.all_types
      expect(types).to be_an(Array)
      entry = types.find { |t| t[:key] == "sql_database" }
      expect(entry).to include(:key, :label, :icon, :description)
    end

    it "skips connector types whose plugin registry entry is disabled" do
      # Use a fake registry where everything is disabled
      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry)
      allow(fake_registry).to receive(:enabled?).and_return(false)
      allow(UndercoverAgents::PluginSystem).to receive(:registry).and_return(fake_registry)

      types = described_class.all_types
      expect(types.pluck(:key)).to contain_exactly("llm_provider")
    end

    it "falls back to description_map when class lacks a .description method" do
      stub_key = "stub_no_desc_#{SecureRandom.hex(4)}"
      no_desc_class = Class.new
      # Use a class name that constantizes to our no-description class
      allow(no_desc_class).to receive(:name).and_return("Object") # Object has no .description
      described_class.register(stub_key, "Object",
                               label: "No Desc", icon: "fa-circle", description: "fallback desc",)
      allow(UndercoverAgents::PluginSystem.registry).to receive(:enabled?).with(stub_key).and_return(true)
      allow(UndercoverAgents::PluginSystem.registry).to receive(:enabled?).and_call_original

      types = described_class.all_types
      entry = types.find { |t| t[:key] == stub_key }
      expect(entry).not_to be_nil
      expect(entry[:description]).to eq("fallback desc")
    end
  end

  describe "default DSL methods from ConnectorPlugin.included block" do
    # A minimal class that includes Configurator + ConnectorPlugin WITHOUT overriding defaults.
    let(:stub_class_bare) do
      Class.new do
        include UndercoverAgents::PluginSystem::Configurator
        include ConnectorPlugin
      end
    end

    # A stub class that overrides permitted_params to return a valid hash
    # (required for build_from_params to produce a valid instance).
    let(:stub_class_with_params) do
      Class.new do
        include UndercoverAgents::PluginSystem::Configurator
        include ConnectorPlugin

        key "stub_conn"
        label "Stub Connector"
        icon "fa-stub"

        def self.permitted_params(_params = nil)
          {}
        end
      end
    end

    it "default permitted_params returns an empty Array" do
      expect(stub_class_bare.permitted_params).to eq([])
    end

    it "build_from_params constructs a new instance via permitted_params" do
      raw = ActionController::Parameters.new(unused: "x")
      instance = stub_class_with_params.build_from_params(raw)
      expect(instance).to be_a(stub_class_with_params)
    end

    it "defaults list_resources metadata to no dedicated kind" do
      expect(stub_class_with_params.list_resources_kind).to be_nil
      expect(stub_class_with_params.list_resources_title).to eq("Stub Connectors")
      expect(stub_class_with_params.supports_model_listing?).to be(false)
      expect(stub_class_with_params.model_provider_key(nil)).to be_nil
    end
  end

  describe "#summary" do
    it "returns the class label for a configurator that does not override summary" do
      stub = Class.new do
        include UndercoverAgents::PluginSystem::Configurator
        include ConnectorPlugin

        label "My Stub Connector"
      end
      expect(stub.new.summary).to eq("My Stub Connector")
    end
  end

  describe "#normalize_blank_credentials" do
    it "skips sensitive keys that the instance does not respond to" do
      stub = Class.new do
        include UndercoverAgents::PluginSystem::Configurator
        include ConnectorPlugin

        key "stub_norm"
        sensitive_keys [:missing_attribute_xyz]
        label "Stub"

        def self.permitted_params(_params = nil) = {}
      end

      instance = stub.new
      # Should not raise even though `missing_attribute_xyz` is not defined
      expect { instance.send(:normalize_blank_credentials) }.not_to raise_error
    end
  end

  describe ".scoped" do
    it "returns the full type scope when Current.tenant is not set" do
      connector = create(:connector, :sql_database)
      Current.reset

      expect(Connectors::SqlDatabase.scoped).to include(connector)
    ensure
      Current.reset
    end

    it "restricts the type scope to the current tenant when one is set" do
      tenant = create(:tenant)
      connector = create(:connector, :sql_database, tenant:)
      create(:connector, :sql_database, tenant: create(:tenant))
      Current.tenant = tenant

      expect(Connectors::SqlDatabase.scoped).to contain_exactly(connector)
    ensure
      Current.reset
    end
  end
end
