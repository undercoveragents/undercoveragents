# frozen_string_literal: true

require "rails_helper"

RSpec.describe CapabilityPlugin do
  # Helper to register a test capability type and clean up afterwards.
  def with_test_capability(key, klass_name, **opts)
    described_class.register(key, klass_name, label: opts.fetch(:label, "Test Label"),
                                              icon: opts.fetch(:icon, "fa-solid fa-star"),
                                              description: opts.fetch(:description, "Test description"),)
    yield
  ensure
    # Reset to remove test-registered types so they don't bleed into other tests.
    described_class.reset!
    # Re-register real capability types after reset.
    UndercoverAgents::PluginSystem.register_capability_types!
  end

  describe ".register" do
    it "raises ArgumentError when registering the same key with a different class" do
      with_test_capability("test_duplicate", "SomeClass") do
        expect do
          described_class.register("test_duplicate", "AnotherClass", label: "X", icon: "X")
        end.to raise_error(ArgumentError, /already registered/)
      end
    end

    it "is idempotent when registering the same key and class again" do
      with_test_capability("test_idempotent", "SameClass") do
        expect do
          described_class.register("test_idempotent", "SameClass", label: "L", icon: "I")
        end.not_to raise_error
      end
    end
  end

  describe ".reset!" do
    it "clears all registered types" do
      original_registry = UndercoverAgents::PluginSystem.registry
      allow(UndercoverAgents::PluginSystem).to receive(:registry).and_return(double(empty?: true))

      described_class.register("test_reset_cap", "Capabilities::TitleGenerator",
                               label: "Test", icon: "fa-test",)
      described_class.reset!

      expect(described_class.type_map).to be_empty
    ensure
      allow(UndercoverAgents::PluginSystem).to receive(:registry).and_return(original_registry) if original_registry
      UndercoverAgents::PluginSystem.register_capability_types!
    end
  end

  describe ".type_map" do
    it "returns a hash of registered type keys to class names" do
      expect(described_class.type_map).to be_a(Hash)
      expect(described_class.type_map).to include("chat_title_generator" => "Capabilities::TitleGenerator")
    end

    it "re-registers capability types after the registry is reset" do
      described_class.reset!

      expect(described_class.type_map).to include("chat_title_generator" => "Capabilities::TitleGenerator")
    ensure
      UndercoverAgents::PluginSystem.register_capability_types!
    end

    it "returns a duplicate (not the internal map)" do
      map = described_class.type_map
      map["injected"] = "Something"
      expect(described_class.type_map).not_to have_key("injected")
    end
  end

  describe ".type_keys" do
    it "returns an array of registered type key strings" do
      keys = described_class.type_keys
      expect(keys).to be_an(Array)
      expect(keys).to include("chat_title_generator")
    end
  end

  describe ".resolve" do
    it "re-registers capability types after the registry is reset" do
      described_class.reset!

      expect(described_class.resolve("chat_title_generator")).to eq(Capabilities::TitleGenerator)
    ensure
      UndercoverAgents::PluginSystem.register_capability_types!
    end

    it "returns nil when the plugin system is unavailable" do
      described_class.reset!
      hide_const("UndercoverAgents::PluginSystem")

      expect(described_class.resolve("chat_title_generator")).to be_nil
    end

    it "returns nil when the plugin registry is empty" do
      described_class.reset!
      original_registry = UndercoverAgents::PluginSystem.registry
      allow(UndercoverAgents::PluginSystem).to receive(:registry).and_return(double(empty?: true))

      expect(described_class.resolve("chat_title_generator")).to be_nil
    ensure
      allow(UndercoverAgents::PluginSystem).to receive(:registry).and_return(original_registry)
      UndercoverAgents::PluginSystem.register_capability_types!
    end

    it "returns nil when re-registering capability types raises" do
      described_class.reset!
      original_registry = UndercoverAgents::PluginSystem.registry
      allow(UndercoverAgents::PluginSystem).to receive(:registry).and_return(double(empty?: false))
      allow(UndercoverAgents::PluginSystem).to receive(:register_capability_types!).and_raise(StandardError, "boom")

      expect(described_class.resolve("chat_title_generator")).to be_nil
    ensure
      allow(UndercoverAgents::PluginSystem).to receive(:registry).and_return(original_registry)
      allow(UndercoverAgents::PluginSystem).to receive(:register_capability_types!).and_call_original
      UndercoverAgents::PluginSystem.register_capability_types!
    end
  end

  describe ".label_for" do
    it "returns the label for a registered type" do
      expect(described_class.label_for("chat_title_generator")).to eq("Chat Title Generator")
    end

    it "returns nil for an unknown type" do
      expect(described_class.label_for("nonexistent_cap")).to be_nil
    end
  end

  describe ".icon_for" do
    it "returns the icon for a registered type" do
      expect(described_class.icon_for("chat_title_generator")).to eq("fa-solid fa-heading")
    end

    it "returns nil for an unknown type" do
      expect(described_class.icon_for("nonexistent_cap")).to be_nil
    end
  end

  describe ".all_types" do
    it "returns type metadata including key, label, icon and description" do
      types = described_class.all_types
      entry = types.find { |t| t[:key] == "chat_title_generator" }

      expect(entry).to include(
        key: "chat_title_generator",
        label: "Chat Title Generator",
        icon: "fa-solid fa-heading",
      )
    end

    context "when a plugin is disabled" do
      it "skips disabled capability types" do
        with_test_capability("disabled_cap", "Capabilities::TitleGenerator", label: "Disabled", icon: "fa-x") do
          UndercoverAgents::PluginSystem.registry.find("disabled_cap")
          allow(UndercoverAgents::PluginSystem.registry).to receive(:enabled?).and_call_original
          allow(UndercoverAgents::PluginSystem.registry).to receive(:enabled?).with("disabled_cap").and_return(false)

          types = described_class.all_types
          expect(types.pluck(:key)).not_to include("disabled_cap")
        end
      end
    end

    context "when capability class does not respond to .description" do
      it "falls back to the description_map value" do
        stub_klass = Class.new do
          # No .description class method
        end
        stub_const("Capabilities::StubNoDescCap", stub_klass)

        with_test_capability("stub_no_desc_cap", "Capabilities::StubNoDescCap",
                             label: "No Desc", icon: "fa-x", description: "Fallback desc",) do
          types = described_class.all_types
          entry = types.find { |t| t[:key] == "stub_no_desc_cap" }
          expect(entry[:description]).to eq("Fallback desc")
        end
      end
    end
  end

  describe "default DSL methods on including class (CapabilityPlugin.included block)" do
    # A minimal capability class that includes Configurator (base) + CapabilityPlugin
    # without overriding the default DSL methods (permitted_params / build_from_params).
    let(:stub_class) do
      Class.new do
        include UndercoverAgents::PluginSystem::Configurator
        include CapabilityPlugin

        key "stub_cap"
        label "Stub Cap"
        icon "fa-stub"
      end
    end

    it "permitted_params returns an empty ActionController::Parameters" do
      raw = ActionController::Parameters.new(foo: "bar")
      result = stub_class.permitted_params(raw)
      expect(result).to be_a(ActionController::Parameters)
      expect(result).to be_empty
    end

    it "build_from_params instantiates from permitted params" do
      raw = ActionController::Parameters.new(unused: "x")
      instance = stub_class.build_from_params(raw)
      expect(instance).to be_a(stub_class)
    end

    it "default event_handler_class returns nil" do
      expect(stub_class.event_handler_class).to be_nil
    end

    it "agent_designer_fields returns names, types, and defaults for configurator attributes" do
      designer_class = Class.new do
        include UndercoverAgents::PluginSystem::Configurator
        include CapabilityPlugin

        attribute :enabled, :boolean, default: true
        attribute :max_items, :integer, default: 3

        key "designer_cap"
        label "Designer Cap"
        icon "fa-designer"
      end

      expect(designer_class.agent_designer_fields).to include(
        { name: "enabled", type: "boolean", default: true },
        { name: "max_items", type: "integer", default: 3 },
      )
    end

    it "summary returns the class label" do
      instance = stub_class.new
      expect(instance.summary).to eq("Stub Cap")
    end

    it "scoped returns an ActiveRecord relation of agents" do
      relation = stub_class.scoped
      expect(relation).to respond_to(:where)
    end
  end
end
