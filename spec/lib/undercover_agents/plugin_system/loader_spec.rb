# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe UndercoverAgents::PluginSystem::Loader do
  subject(:loader) { described_class.new(app_config, Rails.root.join("plugins"), registry) }

  let(:paths) { Hash.new { |hash, key| hash[key] = [] } }
  let(:asset_config_class) { Struct.new(:paths, keyword_init: true) }
  let(:i18n_config_class) { Struct.new(:load_path, keyword_init: true) }
  let(:app_config_class) do
    Struct.new(:paths, :autoload_paths, :eager_load_paths, :assets, :i18n, keyword_init: true)
  end
  let(:assets) { asset_config_class.new(paths: []) }
  let(:i18n) { i18n_config_class.new(load_path: []) }
  let(:app_config) do
    app_config_class.new(
      paths:,
      autoload_paths: [],
      eager_load_paths: [],
      assets:,
      i18n:,
    )
  end
  let(:registry) { UndercoverAgents::PluginSystem::Registry.new }
  let(:tracking_loader_class) do
    Class.new(described_class) do
      attr_reader :configured_definitions
      attr_writer :latest_definition

      def initialize(...)
        super
        @configured_definitions = []
      end

      private

      def find_latest_definition(*)
        @latest_definition
      end

      def configure_paths(definition)
        @configured_definitions << definition
      end
    end
  end

  before do
    allow(Rails.autoloaders.main).to receive(:push_dir)
  end

  describe "#find_latest_definition" do
    it "falls back to the newest registered definition when root paths are not set" do
      old_definition = UndercoverAgents::PluginSystem::Definition.new("old_plugin")
      old_definition.root_path = Pathname.new("/tmp/old_plugin")
      new_definition = UndercoverAgents::PluginSystem::Definition.new("new_plugin")
      registry.register(old_definition)
      registry.register(new_definition)

      result = loader.send(:find_latest_definition, Pathname.new("/tmp/new_plugin"), [old_definition.identifier])

      expect(result).to eq(new_definition)
    end
  end

  describe "#load_plugin" do
    it "returns when a manifest does not register a plugin definition" do
      Dir.mktmpdir do |tmpdir|
        manifest_path = File.join(tmpdir, "plugin.rb")
        File.write(manifest_path, "# no registration\n")

        expect do
          loader.send(:load_plugin, manifest_path, configure_paths: true)
        end.not_to raise_error
      end
    end

    it "skips path configuration when configure_paths is false" do
      Dir.mktmpdir do |tmpdir|
        manifest_path = File.join(tmpdir, "plugin.rb")
        File.write(manifest_path, "# manifest handled via stub\n")
        definition = UndercoverAgents::PluginSystem::Definition.new("loader_test_plugin")
        test_loader = tracking_loader_class.new(app_config, Rails.root.join("plugins"), registry)
        test_loader.latest_definition = definition

        test_loader.send(:load_plugin, manifest_path, configure_paths: false)

        expect(test_loader.configured_definitions).to eq([])
      end
    end

    it "swallows manifest errors when Rails.logger is nil" do
      Dir.mktmpdir do |tmpdir|
        manifest_path = File.join(tmpdir, "plugin.rb")
        File.write(manifest_path, "raise 'boom'\n")
        allow(Rails).to receive(:logger).and_return(nil)

        expect do
          loader.send(:load_plugin, manifest_path, configure_paths: true)
        end.not_to raise_error
      end
    end
  end

  describe "#configure_paths" do
    it "skips regular autoload path registration for custom namespaced connector models" do
      Dir.mktmpdir do |tmpdir|
        plugin_root = Pathname.new(tmpdir)
        FileUtils.mkdir_p(plugin_root.join("app", "models"))
        FileUtils.mkdir_p(plugin_root.join("app", "views"))

        definition = UndercoverAgents::PluginSystem::Definition.new("connector_demo")
        definition.category [:connector]
        definition.root_path = plugin_root

        loader.send(:configure_paths, definition)

        expect(app_config.autoload_paths).not_to include(plugin_root.join("app", "models").to_s)
        expect(app_config.eager_load_paths).not_to include(plugin_root.join("app", "models").to_s)
      end
    end

    it "skips app path registration when the plugin has no app directory" do
      Dir.mktmpdir do |tmpdir|
        plugin_root = Pathname.new(tmpdir)

        definition = UndercoverAgents::PluginSystem::Definition.new("no_app_plugin")
        definition.category [:general]
        definition.root_path = plugin_root

        loader.send(:configure_paths, definition)

        expect(app_config.autoload_paths).to eq([])
        expect(app_config.eager_load_paths).to eq([])
      end
    end

    it "replaces frozen autoload and eager-load arrays instead of mutating them" do
      frozen_config = app_config_class.new(
        paths:,
        autoload_paths: [].freeze,
        eager_load_paths: [].freeze,
        assets:,
        i18n:,
      )
      frozen_loader = described_class.new(frozen_config, Rails.root.join("plugins"), registry)

      Dir.mktmpdir do |tmpdir|
        plugin_root = Pathname.new(tmpdir)
        FileUtils.mkdir_p(plugin_root.join("app", "services"))
        FileUtils.mkdir_p(plugin_root.join("app", "views"))

        definition = UndercoverAgents::PluginSystem::Definition.new("frozen_paths_plugin")
        definition.category [:general]
        definition.root_path = plugin_root

        expect { frozen_loader.send(:configure_paths, definition) }.not_to raise_error
        expect(frozen_config.autoload_paths).to include(plugin_root.join("app", "services").to_s)
        expect(frozen_config.eager_load_paths).to include(plugin_root.join("app", "services").to_s)
      end
    end

    it "leaves asset paths unchanged when a plugin has no asset or javascript directories" do
      Dir.mktmpdir do |tmpdir|
        plugin_root = Pathname.new(tmpdir)
        FileUtils.mkdir_p(plugin_root.join("app", "views"))

        definition = UndercoverAgents::PluginSystem::Definition.new("plain_plugin")
        definition.category [:general]
        definition.root_path = plugin_root

        loader.send(:configure_paths, definition)

        expect(app_config.assets.paths).to eq([])
      end
    end

    it "skips asset handling when the app config does not expose asset paths" do
      config_without_assets_class = Struct.new(:paths, :autoload_paths, :eager_load_paths, :i18n, keyword_init: true)
      config_without_assets = config_without_assets_class.new(
        paths: Hash.new { |hash, key| hash[key] = [] },
        autoload_paths: [],
        eager_load_paths: [],
        i18n: i18n_config_class.new(load_path: []),
      )
      loader_without_assets = described_class.new(config_without_assets, Rails.root.join("plugins"), registry)

      Dir.mktmpdir do |tmpdir|
        plugin_root = Pathname.new(tmpdir)
        definition = UndercoverAgents::PluginSystem::Definition.new("assetless_config_plugin")
        definition.category [:general]
        definition.root_path = plugin_root

        expect { loader_without_assets.send(:configure_paths, definition) }.not_to raise_error
      end
    end

    it "ignores non-directory entries inside the assets folder" do
      Dir.mktmpdir do |tmpdir|
        plugin_root = Pathname.new(tmpdir)
        FileUtils.mkdir_p(plugin_root.join("app", "assets", "images"))
        FileUtils.mkdir_p(plugin_root.join("app", "views"))
        File.write(plugin_root.join("app", "assets", "manifest.txt"), "asset manifest")

        definition = UndercoverAgents::PluginSystem::Definition.new("assets_plugin")
        definition.category [:general]
        definition.root_path = plugin_root

        loader.send(:configure_paths, definition)

        expect(app_config.assets.paths).to include(plugin_root.join("app", "assets", "images").to_s)
        expect(app_config.assets.paths).not_to include(plugin_root.join("app", "assets", "manifest.txt").to_s)
      end
    end

    it "returns early when the plugin has no views directory" do
      Dir.mktmpdir do |tmpdir|
        plugin_root = Pathname.new(tmpdir)

        definition = UndercoverAgents::PluginSystem::Definition.new("no_views_plugin")
        definition.category [:general]
        definition.root_path = plugin_root

        loader.send(:configure_paths, definition)

        expect(app_config.paths["app/views"]).to eq([])
      end
    end

    it "skips tool namespace loading for multi-category plugins" do
      Dir.mktmpdir do |tmpdir|
        plugin_root = Pathname.new(tmpdir)
        FileUtils.mkdir_p(plugin_root.join("app", "models"))
        FileUtils.mkdir_p(plugin_root.join("app", "services"))

        definition = UndercoverAgents::PluginSystem::Definition.new("tool_combo")
        allow(definition).to receive_messages(only_tool_plugin?: true, connector_plugin?: true,
                                              tool_plugin?: true, rag_step_plugin?: false,)
        definition.root_path = plugin_root

        loader.send(:configure_tool_namespaced_paths, definition, plugin_root.join("app"))

        expect(Rails.autoloaders.main).not_to have_received(:push_dir)
      end
    end

    it "configures channel namespaced paths for channel plugins" do
      Dir.mktmpdir do |tmpdir|
        definition = UndercoverAgents::PluginSystem::Definition.new("channel_demo")
        definition.category [:channel]
        app_dir = Pathname.new(tmpdir).join("app")
        FileUtils.mkdir_p(app_dir.join("models", "channels"))

        loader.send(:configure_channel_namespaced_paths, definition, app_dir)

        expect(Rails.autoloaders.main).to have_received(:push_dir)
          .with(app_dir.join("models", "channels").to_s, namespace: Channels)
      end
    end
  end

  describe "#handled_by_custom_namespace_loader?" do
    it "returns false for multi-category plugins" do
      definition = UndercoverAgents::PluginSystem::Definition.new("combo_plugin")
      definition.category [:connector, :tool]

      expect(loader.send(:handled_by_custom_namespace_loader?, definition, "models")).to be(false)
    end
  end

  describe "#configure_namespaced_path" do
    it "ignores missing directories" do
      missing_path = Pathname.new("/tmp/definitely_missing_plugin_path")

      loader.send(:configure_namespaced_path, missing_path, Connectors)

      expect(Rails.autoloaders.main).not_to have_received(:push_dir)
    end
  end

  context "with Rails application config" do
    let(:app_config) { Rails.application.config }

    describe "#load_all!" do
      it "does nothing when plugins path does not exist" do
        described_class.new(app_config, "/nonexistent/path", registry).load_all!
        expect(registry.count).to eq(0)
      end

      it "discovers plugin manifests via Dir.glob" do
        manifests = loader.send(:discover_manifests)
        expect(manifests).not_to be_empty
        expect(manifests).to all(end_with("plugin.rb"))
      end

      it "logs error and continues when a plugin fails to load" do
        Dir.mktmpdir do |tmpdir|
          plugin_dir = File.join(tmpdir, "broken_plugin")
          FileUtils.mkdir_p(plugin_dir)
          File.write(File.join(plugin_dir, "plugin.rb"), "raise 'Intentional test error'\n")
          allow(Rails.logger).to receive(:error)

          described_class.new(app_config, tmpdir, registry).load_all!

          expect(Rails.logger).to have_received(:error).with(/Failed to load plugin/)
        end
      end
    end

    describe "rag-step path handling" do
      it "uses namespaced loaders for rag-step plugin categories" do
        definition = UndercoverAgents::PluginSystem::Definition.new("chunker")
        definition.category [:rag_chunking]

        expect(loader.send(:handled_by_custom_namespace_loader?, definition, "models")).to be(true)
        expect(loader.send(:handled_by_custom_namespace_loader?, definition, "services")).to be(true)
        expect(loader.send(:handled_by_custom_namespace_loader?, definition, "controllers")).to be(false)
      end

      it "does not use namespaced loaders for non-rag plugins" do
        definition = UndercoverAgents::PluginSystem::Definition.new("other")
        definition.category [:general]

        expect(loader.send(:handled_by_custom_namespace_loader?, definition, "models")).to be(false)
      end

      it "configures rag-step namespaced paths when plugin is rag-step capable" do
        Dir.mktmpdir do |tmpdir|
          definition = UndercoverAgents::PluginSystem::Definition.new("embedder")
          definition.category [:rag_embedding]
          app_dir = Pathname.new(tmpdir).join("app")
          FileUtils.mkdir_p(app_dir.join("models"))
          FileUtils.mkdir_p(app_dir.join("services"))
          stub_const("RagSteps", Module.new)
          stub_const("Rag", Module.new)

          loader.send(:configure_rag_step_namespaced_paths, definition, app_dir)

          expect(Rails.autoloaders.main).to have_received(:push_dir)
            .with(app_dir.join("models").to_s, namespace: RagSteps)
          expect(Rails.autoloaders.main).to have_received(:push_dir).with(app_dir.join("services").to_s, namespace: Rag)
        end
      end

      it "skips rag-step namespaced paths for non-rag plugins" do
        Dir.mktmpdir do |tmpdir|
          definition = UndercoverAgents::PluginSystem::Definition.new("general")
          definition.category [:general]
          app_dir = Pathname.new(tmpdir).join("app")
          FileUtils.mkdir_p(app_dir.join("models"))
          FileUtils.mkdir_p(app_dir.join("services"))

          loader.send(:configure_rag_step_namespaced_paths, definition, app_dir)

          expect(Rails.autoloaders.main).not_to have_received(:push_dir)
        end
      end
    end
  end
end
