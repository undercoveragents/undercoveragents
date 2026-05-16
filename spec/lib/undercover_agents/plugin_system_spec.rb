# frozen_string_literal: true

require "rails_helper"

RSpec.describe UndercoverAgents::PluginSystem do
  describe ".registry" do
    it "returns a Registry instance" do
      expect(described_class.registry).to be_a(UndercoverAgents::PluginSystem::Registry)
    end

    it "returns the same instance on multiple calls" do
      expect(described_class.registry).to equal(described_class.registry)
    end
  end

  describe ".register" do
    after { described_class.registry }

    it "registers a plugin definition via a block DSL" do
      definition = described_class.register("spec_test_register_block") do
        name "Spec Test"
        version "1.0.0"
      end

      expect(definition).to be_a(UndercoverAgents::PluginSystem::Definition)
      expect(definition.frozen?).to be(true)
      expect(definition.name).to eq("Spec Test")
      found = described_class.registry.find("spec_test_register_block")
      expect(found).to eq(definition)
    end

    it "supports legacy block argument style" do
      definition = described_class.register("spec_test_register_legacy") do |plugin|
        plugin.name = "Legacy Style"
      end

      expect(definition.name).to eq("Legacy Style")
      expect(described_class.registry.find("spec_test_register_legacy")).to eq(definition)
    end

    it "registers with defaults when no block is provided" do
      definition = described_class.register("spec_test_register_no_block")

      expect(definition.identifier).to eq("spec_test_register_no_block")
      expect(definition.name).to be_nil
      expect(described_class.registry.find("spec_test_register_no_block")).to eq(definition)
    end
  end

  describe ".sync_database!" do
    it "calls sync_with_database! on the registry" do
      allow(described_class.registry).to receive(:sync_with_database!)
      described_class.sync_database!
      expect(described_class.registry).to have_received(:sync_with_database!)
    end

    it "does not call sync if Plugin is not defined" do
      allow(described_class.registry).to receive(:sync_with_database!)
      # Simulate Plugin not being defined by stubbing the check
      hide_const("Plugin")
      described_class.sync_database!
      expect(described_class.registry).not_to have_received(:sync_with_database!)
    end
  end

  describe ".load!" do
    it "creates a Loader and calls load_all!" do
      loader = instance_double(UndercoverAgents::PluginSystem::Loader, load_all!: nil)
      allow(UndercoverAgents::PluginSystem::Loader).to receive(:new).and_return(loader)

      described_class.load!(Rails.application.config, Rails.root.join("plugins"))

      expect(loader).to have_received(:load_all!)
    end
  end

  describe ".reload_manifests!" do
    # rubocop:disable RSpec/ExampleLength
    it "clears registry, resets plugin registries and reloads without configuring paths", :aggregate_failures do
      loader = instance_double(UndercoverAgents::PluginSystem::Loader, load_all!: nil)
      allow(UndercoverAgents::PluginSystem::Loader).to receive(:new).and_return(loader)
      allow(described_class.registry).to receive(:clear_definitions!)
      allow(described_class).to receive(:register_step_types!)
      allow(described_class).to receive(:register_connector_types!)
      allow(described_class).to receive(:register_capability_types!)
      allow(described_class).to receive(:register_tool_types!)
      allow(described_class).to receive(:register_channel_types!)
      allow(described_class).to receive(:sync_database!)
      allow(RagStepPlugin).to receive(:reset!)
      allow(ConnectorPlugin).to receive(:reset!)
      allow(CapabilityPlugin).to receive(:reset!)
      allow(ToolPlugin).to receive(:reset!)
      allow(ChannelPlugin).to receive(:reset!)

      described_class.reload_manifests!(Rails.application.config, Rails.root.join("plugins"))

      expect(described_class.registry).to have_received(:clear_definitions!)
      expect(RagStepPlugin).to have_received(:reset!)
      expect(ConnectorPlugin).to have_received(:reset!)
      expect(CapabilityPlugin).to have_received(:reset!)
      expect(ToolPlugin).to have_received(:reset!)
      expect(ChannelPlugin).to have_received(:reset!)
      expect(loader).to have_received(:load_all!).with(configure_paths: false)
      expect(described_class).to have_received(:register_step_types!)
      expect(described_class).to have_received(:register_connector_types!)
      expect(described_class).to have_received(:register_capability_types!)
      expect(described_class).to have_received(:register_tool_types!)
      expect(described_class).to have_received(:register_channel_types!)
      expect(described_class).to have_received(:sync_database!)
    end

    it "skips registry resets for plugin systems that are not loaded" do
      loader = instance_double(UndercoverAgents::PluginSystem::Loader, load_all!: nil)
      allow(UndercoverAgents::PluginSystem::Loader).to receive(:new).and_return(loader)
      allow(described_class.registry).to receive(:clear_definitions!)
      allow(described_class).to receive(:register_step_types!)
      allow(described_class).to receive(:register_connector_types!)
      allow(described_class).to receive(:register_capability_types!)
      allow(described_class).to receive(:register_tool_types!)
      allow(described_class).to receive(:register_channel_types!)
      allow(described_class).to receive(:sync_database!)
      hide_const("RagStepPlugin")
      hide_const("ConnectorPlugin")
      hide_const("CapabilityPlugin")
      hide_const("ToolPlugin")
      hide_const("ChannelPlugin")

      expect do
        described_class.reload_manifests!(Rails.application.config, Rails.root.join("plugins"))
      end.not_to raise_error
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe ".register_step_types!" do
    it "registers step types from rag-step entry points" do
      allow(RagStepPlugin).to receive(:register)

      described_class.register_step_types!

      expect(RagStepPlugin).to have_received(:register).at_least(:once)
    end

    it "uses suffixed keys when a plugin registers multiple rag entry points" do
      definition = UndercoverAgents::PluginSystem::Definition.new("multi_feature")
      definition.category [:rag_chunking, :rag_embedding]
      definition.add_rag_chunker("FixedSizeChunker")
      definition.add_rag_embedding("LlmEmbedder")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(RagStepPlugin).to receive(:register)

      described_class.register_step_types!

      expect(RagStepPlugin).to have_received(:register).with(
        "fixed_size_chunker",
        "RagSteps::FixedSizeChunker",
        label: "Fixed Size",
        icon: "fa-solid fa-ruler",
        stage: :chunking,
      )
      expect(RagStepPlugin).to have_received(:register).with(
        "llm_embedder",
        "RagSteps::LlmEmbedder",
        label: "LLM Embedder",
        icon: "fa-solid fa-vector-square",
        stage: :embedding,
      )
    end

    it "falls back to suffixed keys when class is not constantized" do
      definition = UndercoverAgents::PluginSystem::Definition.new("multi_feature")
      definition.category [:rag_chunking, :rag_embedding]
      definition.add_rag_chunker("MissingChunker")
      definition.add_rag_embedding("MissingEmbedder")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(RagStepPlugin).to receive(:register)

      described_class.register_step_types!

      expect(RagStepPlugin).to have_received(:register).with(
        "multi_feature_chunking",
        "RagSteps::MissingChunker",
        label: "Multi Feature Chunking",
        icon: "fa-solid fa-puzzle-piece",
        stage: :chunking,
      )
      expect(RagStepPlugin).to have_received(:register).with(
        "multi_feature_embedding",
        "RagSteps::MissingEmbedder",
        label: "Multi Feature Embedding",
        icon: "fa-solid fa-puzzle-piece",
        stage: :embedding,
      )
    end

    it "skips plugins without rag entry points" do
      definition = UndercoverAgents::PluginSystem::Definition.new("metadata_only")
      definition.category [:general]

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(RagStepPlugin).to receive(:register)

      described_class.register_step_types!

      expect(RagStepPlugin).not_to have_received(:register)
    end

    it "keeps fully namespaced class names as-is" do
      definition = UndercoverAgents::PluginSystem::Definition.new("namespaced_plugin")
      definition.category [:rag_chunking]
      definition.add_rag_chunker("RagSteps::FixedSizeChunker")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(RagStepPlugin).to receive(:register)

      described_class.register_step_types!

      expect(RagStepPlugin).to have_received(:register).with(
        "fixed_size_chunker",
        "RagSteps::FixedSizeChunker",
        label: "Fixed Size",
        icon: "fa-solid fa-ruler",
        stage: :chunking,
      )
    end

    it "uses plugin identifier for single missing entry point" do
      definition = UndercoverAgents::PluginSystem::Definition.new("single_missing")
      definition.category [:rag_chunking]
      definition.add_rag_chunker("MissingSingleChunker")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(RagStepPlugin).to receive(:register)

      described_class.register_step_types!

      expect(RagStepPlugin).to have_received(:register).with(
        "single_missing",
        "RagSteps::MissingSingleChunker",
        label: "Single Missing",
        icon: "fa-solid fa-puzzle-piece",
        stage: :chunking,
      )
    end

    it "uses plugin identifier when class exists without key and entry point is single" do
      stub_const("RagSteps::NoTypeKeySingle", Class.new)

      definition = UndercoverAgents::PluginSystem::Definition.new("no_type_key_single")
      definition.category [:rag_chunking]
      definition.add_rag_chunker("NoTypeKeySingle")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(RagStepPlugin).to receive(:register)

      described_class.register_step_types!

      expect(RagStepPlugin).to have_received(:register).with(
        "no_type_key_single",
        "RagSteps::NoTypeKeySingle",
        label: "No Type Key Single",
        icon: "fa-solid fa-puzzle-piece",
        stage: :chunking,
      )
    end

    it "uses suffixed key when class exists without key and entry points are multiple" do
      stub_const("RagSteps::NoTypeKeyChunker", Class.new)
      stub_const("RagSteps::NoTypeKeyEmbedder", Class.new)

      definition = UndercoverAgents::PluginSystem::Definition.new("no_type_key_multi")
      definition.category [:rag_chunking, :rag_embedding]
      definition.add_rag_chunker("NoTypeKeyChunker")
      definition.add_rag_embedding("NoTypeKeyEmbedder")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(RagStepPlugin).to receive(:register)

      described_class.register_step_types!

      expect(RagStepPlugin).to have_received(:register).with(
        "no_type_key_multi_chunking",
        "RagSteps::NoTypeKeyChunker",
        label: "No Type Key Multi Chunking",
        icon: "fa-solid fa-puzzle-piece",
        stage: :chunking,
      )
      expect(RagStepPlugin).to have_received(:register).with(
        "no_type_key_multi_embedding",
        "RagSteps::NoTypeKeyEmbedder",
        label: "No Type Key Multi Embedding",
        icon: "fa-solid fa-puzzle-piece",
        stage: :embedding,
      )
    end
  end

  describe ".register_connector_types!" do
    it "returns early when ConnectorPlugin is not loaded" do
      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry)
      allow(fake_registry).to receive(:all).and_return([])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      hide_const("ConnectorPlugin")

      expect { described_class.register_connector_types! }.not_to raise_error
      expect(fake_registry).not_to have_received(:all)
    end

    it "falls back to identifier-based metadata when connector class is missing" do
      definition = UndercoverAgents::PluginSystem::Definition.new("connector_my_service")
      definition.category [:connector]
      definition.name "My Service"
      definition.icon "fa-solid fa-server"
      definition.description "A service connector"
      definition.add_connector("MissingConnectorClass")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(ConnectorPlugin).to receive(:register)
      allow(ConnectorPlugin).to receive(:register_core_types!)

      described_class.register_connector_types!

      expect(ConnectorPlugin).to have_received(:register).with(
        "my_service",
        "Connectors::MissingConnectorClass",
        label: "My Service",
        icon: "fa-solid fa-server",
        description: "A service connector",
      )
    end

    it "uses definition description when connector class exists but has no description method" do
      stub_const("Connectors::NoDescConnector", Class.new)

      definition = UndercoverAgents::PluginSystem::Definition.new("connector_no_desc")
      definition.category [:connector]
      definition.name "No Desc"
      definition.description "Fallback description"
      definition.add_connector("NoDescConnector")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(ConnectorPlugin).to receive(:register)
      allow(ConnectorPlugin).to receive(:register_core_types!)

      described_class.register_connector_types!

      expect(ConnectorPlugin).to have_received(:register).with(
        anything,
        anything,
        hash_including(description: "Fallback description"),
      )
    end

    it "skips plugins without connector entry points" do
      definition = UndercoverAgents::PluginSystem::Definition.new("rag_only_plugin")
      definition.category [:rag_chunking]

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(ConnectorPlugin).to receive(:register)
      allow(ConnectorPlugin).to receive(:register_core_types!)

      described_class.register_connector_types!

      expect(ConnectorPlugin).not_to have_received(:register)
    end

    it "keeps fully namespaced connector class names as-is" do
      definition = UndercoverAgents::PluginSystem::Definition.new("connector_already_namespaced")
      definition.category [:connector]
      definition.name "Already Namespaced"
      definition.description "desc"
      definition.add_connector("Connectors::SqlDatabase")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(ConnectorPlugin).to receive(:register)
      allow(ConnectorPlugin).to receive(:register_core_types!)

      described_class.register_connector_types!

      expect(ConnectorPlugin).to have_received(:register).with(
        anything,
        "Connectors::SqlDatabase",
        anything,
      )
    end
  end

  describe ".register_capability_types!" do
    it "returns early when CapabilityPlugin is not loaded" do
      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry)
      allow(fake_registry).to receive(:all).and_return([])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      hide_const("CapabilityPlugin")

      expect { described_class.register_capability_types! }.not_to raise_error
      expect(fake_registry).not_to have_received(:all)
    end

    it "falls back to identifier-based metadata when capability class is missing" do
      definition = UndercoverAgents::PluginSystem::Definition.new("capability_my_feature")
      definition.category [:capability]
      definition.name "My Feature"
      definition.icon "fa-solid fa-star"
      definition.description "A feature capability"
      definition.add_capability("MissingCapabilityClass")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(CapabilityPlugin).to receive(:register)

      described_class.register_capability_types!

      expect(CapabilityPlugin).to have_received(:register).with(
        "my_feature",
        "Capabilities::MissingCapabilityClass",
        label: "My Feature",
        icon: "fa-solid fa-star",
        description: "A feature capability",
      )
    end

    it "uses definition description when capability class exists but has no description method" do
      stub_const("Capabilities::NoDescCapability", Class.new)

      definition = UndercoverAgents::PluginSystem::Definition.new("capability_no_desc")
      definition.category [:capability]
      definition.name "No Desc"
      definition.description "Fallback capability description"
      definition.add_capability("NoDescCapability")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(CapabilityPlugin).to receive(:register)

      described_class.register_capability_types!

      expect(CapabilityPlugin).to have_received(:register).with(
        anything,
        anything,
        hash_including(description: "Fallback capability description"),
      )
    end

    it "skips plugins without capability entry points" do
      definition = UndercoverAgents::PluginSystem::Definition.new("rag_only_plugin2")
      definition.category [:rag_chunking]

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(CapabilityPlugin).to receive(:register)

      described_class.register_capability_types!

      expect(CapabilityPlugin).not_to have_received(:register)
    end

    it "keeps fully namespaced capability class names as-is" do
      definition = UndercoverAgents::PluginSystem::Definition.new("capability_namespaced")
      definition.category [:capability]
      definition.name "Namespaced Cap"
      definition.description "desc"
      definition.add_capability("Capabilities::TitleGenerator")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(CapabilityPlugin).to receive(:register)

      described_class.register_capability_types!

      expect(CapabilityPlugin).to have_received(:register).with(
        anything,
        "Capabilities::TitleGenerator",
        anything,
      )
    end
  end

  describe ".register_channel_types!" do
    it "returns early when ChannelPlugin is not loaded" do
      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry)
      allow(fake_registry).to receive(:all).and_return([])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      hide_const("ChannelPlugin")

      expect { described_class.register_channel_types! }.not_to raise_error
      expect(fake_registry).not_to have_received(:all)
    end

    it "falls back to identifier-based metadata when the channel class is missing" do
      definition = UndercoverAgents::PluginSystem::Definition.new("channel_slack")
      definition.category [:channel]
      definition.name "Slack"
      definition.icon "fa-brands fa-slack"
      definition.description "Slack channel"
      definition.add_channel("MissingSlack")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(ChannelPlugin).to receive(:register)
      allow(ChannelPlugin).to receive(:register_core_types!)

      described_class.register_channel_types!

      expect(ChannelPlugin).to have_received(:register).with(
        "slack",
        "Channels::MissingSlack",
        label: "Slack",
        icon: "fa-brands fa-slack",
        description: "Slack channel",
      )
    end

    it "uses the definition description when the channel class has no description method" do
      stub_const("Channels::NoDescChannel", Class.new)

      definition = UndercoverAgents::PluginSystem::Definition.new("channel_no_desc")
      definition.category [:channel]
      definition.name "No Desc"
      definition.description "Fallback channel description"
      definition.add_channel("NoDescChannel")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(ChannelPlugin).to receive(:register)
      allow(ChannelPlugin).to receive(:register_core_types!)

      described_class.register_channel_types!

      expect(ChannelPlugin).to have_received(:register).with(
        anything,
        anything,
        hash_including(description: "Fallback channel description"),
      )
    end

    it "keeps fully namespaced channel class names as-is" do
      definition = UndercoverAgents::PluginSystem::Definition.new("channel_namespaced")
      definition.category [:channel]
      definition.name "Namespaced Channel"
      definition.icon "fa-solid fa-tower-broadcast"
      definition.description "desc"
      definition.add_channel("Channels::Client")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(ChannelPlugin).to receive(:register)
      allow(ChannelPlugin).to receive(:register_core_types!)

      described_class.register_channel_types!

      expect(ChannelPlugin).to have_received(:register).with(
        anything,
        "Channels::Client",
        anything,
      )
    end
  end

  describe ".reset!" do
    it "creates a new registry instance" do
      old_registry = described_class.registry
      described_class.reset!
      expect(described_class.registry).not_to equal(old_registry)

      # Re-load plugins to restore state for subsequent tests
      described_class.load!(Rails.application.config, Rails.root.join("plugins"))
      described_class.register_step_types!
      described_class.register_connector_types!
      described_class.register_capability_types!
      described_class.register_channel_types!
    end
  end

  describe ".register_tool_types!" do
    it "returns early when ToolPlugin is not loaded" do
      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry)
      allow(fake_registry).to receive(:all).and_return([])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      hide_const("ToolPlugin")

      expect { described_class.register_tool_types! }.not_to raise_error
      expect(fake_registry).not_to have_received(:all)
    end

    it "falls back to identifier-based metadata when tool class is missing" do
      definition = UndercoverAgents::PluginSystem::Definition.new("tool_missing")
      definition.category [:tool]
      definition.name "Missing Tool"
      definition.icon "fa-solid fa-screwdriver-wrench"
      definition.description "Fallback tool description"
      definition.add_tool("MissingToolClass")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(ToolPlugin).to receive(:register)

      described_class.register_tool_types!

      expect(ToolPlugin).to have_received(:register).with(
        "missing",
        "Tools::MissingToolClass",
        label: "Missing Tool",
        icon: "fa-solid fa-screwdriver-wrench",
        description: "Fallback tool description",
      )
    end

    it "keeps fully namespaced tool class names as-is" do
      definition = UndercoverAgents::PluginSystem::Definition.new("tool_namespaced")
      definition.category [:tool]
      definition.name "Namespaced Tool"
      definition.icon "fa-solid fa-wrench"
      definition.description "desc"
      definition.add_tool("Tools::SqlQuery")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(ToolPlugin).to receive(:register)

      described_class.register_tool_types!

      expect(ToolPlugin).to have_received(:register).with(
        anything,
        "Tools::SqlQuery",
        anything,
      )
    end

    it "prefers the tool class description when the class defines one" do
      stub_const("Tools::DocumentedTool", Class.new do
        def self.description = "Documented tool description"
      end,)

      definition = UndercoverAgents::PluginSystem::Definition.new("tool_documented")
      definition.category [:tool]
      definition.name "Documented Tool"
      definition.icon "fa-solid fa-book"
      definition.description "Fallback tool description"
      definition.add_tool("DocumentedTool")

      fake_registry = instance_double(UndercoverAgents::PluginSystem::Registry, all: [definition])
      allow(described_class).to receive(:registry).and_return(fake_registry)
      allow(ToolPlugin).to receive(:register)

      described_class.register_tool_types!

      expect(ToolPlugin).to have_received(:register).with(
        "documented",
        "Tools::DocumentedTool",
        label: "Documented Tool",
        icon: "fa-solid fa-book",
        description: "Documented tool description",
      )
    end
  end
end
