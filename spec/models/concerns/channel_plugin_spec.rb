# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelPlugin do
  before do
    described_class.reset!
    UndercoverAgents::PluginSystem.register_channel_types!
  end

  after do
    described_class.reset!
    UndercoverAgents::PluginSystem.register_channel_types!
  rescue StandardError
    nil
  end

  it "registers app-owned core channel types" do
    expect(described_class.type_keys).to include("client", "api")
    expect(described_class.resolve("client")).to eq(Channels::Client)
    expect(described_class.label_for("api")).to eq("API")
  end

  it "returns metadata for enabled app-owned channel types" do
    expect(described_class.all_types).to include(
      hash_including(key: "client", label: "Client", icon: "fa-solid fa-comments"),
    )
  end

  describe ".register" do
    it "allows idempotent registration for the same class" do
      expect do
        described_class.register(
          "spec_plugin",
          "Channels::Client",
          label: "Spec Plugin",
          icon: "fa-solid fa-flask",
          description: "Spec plugin",
        )
        described_class.register(
          "spec_plugin",
          "Channels::Client",
          label: "Spec Plugin",
          icon: "fa-solid fa-flask",
          description: "Spec plugin",
        )
      end.not_to raise_error
    end

    it "rejects registering a different class for the same key" do
      described_class.register(
        "spec_plugin",
        "Channels::Client",
        label: "Spec Plugin",
        icon: "fa-solid fa-flask",
        description: "Spec plugin",
      )

      expect do
        described_class.register(
          "spec_plugin",
          "Channels::Api",
          label: "Spec Plugin",
          icon: "fa-solid fa-flask",
          description: "Spec plugin",
        )
      end.to raise_error(ArgumentError, "Channel type 'spec_plugin' is already registered")
    end
  end

  describe ".all_types" do
    it "filters plugin-owned channel types by enabled state" do
      described_class.register(
        "spec_plugin",
        "Channels::Client",
        label: "Spec Plugin",
        icon: "fa-solid fa-flask",
        description: "Spec plugin",
      )
      registry = instance_double(UndercoverAgents::PluginSystem::Registry)

      allow(UndercoverAgents::PluginSystem).to receive(:registry).and_return(registry)
      allow(registry).to receive_messages(all: [], enabled?: false)
      allow(registry).to receive(:enabled?).with("spec_plugin").and_return(false)

      expect(described_class.all_types).not_to include(hash_including(key: "spec_plugin"))

      allow(registry).to receive(:enabled?).with("spec_plugin").and_return(true)

      expect(described_class.all_types).to include(hash_including(key: "spec_plugin", label: "Spec Plugin"))
      expect(described_class.app_owned?("client")).to be(true)
      expect(described_class.app_owned?("spec_plugin")).to be(false)
    end

    it "falls back to the stored description when the class does not define one" do
      stub_const("Channels::NoDescriptionChannel", Class.new)

      described_class.register(
        "no_description",
        "Channels::NoDescriptionChannel",
        label: "No Description",
        icon: "fa-solid fa-circle",
        description: "Stored description",
        source: :app,
      )

      expect(described_class.all_types).to include(
        hash_including(key: "no_description", description: "Stored description"),
      )
    end
  end

  describe ".type_map" do
    it "returns an empty map when bootstrap registration fails" do
      described_class.reset!
      allow(UndercoverAgents::PluginSystem).to receive(:register_channel_types!).and_raise(StandardError)

      expect(described_class.type_map).to eq({})
    end

    it "returns early when the plugin registry is empty and no channel types are registered" do
      described_class.reset!
      registry = instance_double(UndercoverAgents::PluginSystem::Registry, empty?: true)
      original_registry = UndercoverAgents::PluginSystem.registry

      allow(UndercoverAgents::PluginSystem).to receive(:registry).and_return(registry, original_registry)
      allow(UndercoverAgents::PluginSystem).to receive(:register_channel_types!).and_call_original

      expect(described_class.type_map).to eq({})
      expect(UndercoverAgents::PluginSystem).not_to have_received(:register_channel_types!)
    end

    it "returns an empty map when the plugin system is not loaded" do
      described_class.reset!
      hide_const("UndercoverAgents::PluginSystem")

      expect(described_class.type_map).to eq({})
    end

    it "re-registers missing plugin channel types after a partial registry reset" do
      described_class.reset!
      described_class.register_core_types!

      expect(described_class.resolve("telegram")).to eq(Channels::Telegram)
    end
  end

  describe "configurator DSL" do
    before do
      stub_const("Channels::SpecCoverageChannel", Class.new do
        include UndercoverAgents::PluginSystem::Configurator
        include ChannelPlugin

        attribute :example, :string

        def self.permitted_params(raw)
          raw.permit(:example)
        end

        key "spec_coverage"
        label "Spec Coverage"
        icon "fa-solid fa-flask"
        description "Used for coverage"
        target_kinds ["mission"]
        requires_connector_type "telegram"
        delivery_adapter_class "Channels::SpecAdapter"
      end,)
    end

    it "exposes the class-level DSL metadata and builds configurators from params", :aggregate_failures do
      params = ActionController::Parameters.new(example: "value").permit!
      configurator = Channels::SpecCoverageChannel.build_from_params(params)

      expect(Channels::SpecCoverageChannel.key).to eq("spec_coverage")
      expect(Channels::SpecCoverageChannel.label).to eq("Spec Coverage")
      expect(Channels::SpecCoverageChannel.icon).to eq("fa-solid fa-flask")
      expect(Channels::SpecCoverageChannel.description).to eq("Used for coverage")
      expect(Channels::SpecCoverageChannel.target_kinds).to eq(["mission"])
      expect(Channels::SpecCoverageChannel.requires_connector_type).to eq("telegram")
      expect(Channels::SpecCoverageChannel.delivery_adapter_class).to eq("Channels::SpecAdapter")
      expect(Channels::SpecCoverageChannel.permitted_params(params)).to be_permitted
      expect(configurator.example).to eq("value")
      expect(configurator.summary).to eq("Spec Coverage")
    end

    it "resolves overridden form and show partial paths for client channels" do
      configurator = Channels::Client.new

      expect(configurator.form_partial_path).to eq(Rails.root.join("app/views/channels/client"))
      expect(configurator.show_partial_path).to eq(Rails.root.join("app/views/channels/client"))
    end

    it "falls back to the default permitted params and partial path behavior" do
      stub_const("Channels::BareSpecCoverageChannel", Class.new do
        include UndercoverAgents::PluginSystem::Configurator
        include ChannelPlugin

        attribute :example, :string

        key "bare_spec_coverage"
        label "Bare Spec Coverage"
        icon "fa-solid fa-vial"
      end,)

      params = ActionController::Parameters.new(example: "value")
      configurator = Channels::BareSpecCoverageChannel.build_from_params(params)
      bare_configurator = Channels::BareSpecCoverageChannel.new
      allow(Object).to receive(:const_source_location).and_call_original
      allow(Object).to receive(:const_source_location)
        .with("Channels::BareSpecCoverageChannel")
        .and_return([Rails.root.join("app/models/channels/bare_spec_coverage_channel.rb").to_s, 1])

      expect(Channels::BareSpecCoverageChannel.permitted_params(params)).to be_permitted
      expect(configurator.example).to be_nil
      expect(bare_configurator.form_partial_path).to eq(Rails.root.join("app/views").to_s)
      expect(bare_configurator.show_partial_path).to eq(Rails.root.join("app/views").to_s)
    end
  end
end
