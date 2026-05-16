# frozen_string_literal: true

module UndercoverAgents
  module PluginSystem
    # Discovers plugins by scanning the plugins directory for plugin.rb manifests.
    # For each plugin, creates a dynamic lightweight Rails::Engine subclass that
    # provides autoloading, view paths, and asset routing — no boilerplate needed
    # per plugin.
    class Loader
      NAMESPACED_PLUGIN_SUBDIRS = {
        rag_step_plugin?: ["models", "services"],
        connector_plugin?: ["models"],
        only_tool_plugin?: ["models", "services", "agents"],
      }.freeze
      def initialize(app_config, plugins_path, registry)
        @app_config = app_config
        @plugins_path = Pathname.new(plugins_path)
        @registry = registry
      end

      def load_all!(configure_paths: true)
        return unless @plugins_path.exist?

        discover_manifests.each do |manifest_path|
          load_plugin(manifest_path, configure_paths:)
        end
      end

      private

      def discover_manifests
        Dir.glob(@plugins_path.join("**/plugin.rb"))
      end

      def load_plugin(manifest_path, configure_paths:)
        plugin_dir = File.dirname(manifest_path)
        previous_ids = @registry.all.map(&:identifier)

        # Evaluate the manifest to register the plugin
        load manifest_path

        # Find the definition that was just registered
        # (The manifest calls UndercoverAgents::PluginSystem.register which adds it)
        definition = find_latest_definition(plugin_dir, previous_ids)
        # :nocov:
        return unless definition
        # :nocov:

        # Set the root path on the definition
        definition.root_path = Pathname.new(plugin_dir)

        # Configure autoloading and view paths directly on the app config
        configure_paths(definition) if configure_paths
      rescue StandardError => e
        # :nocov:
        if defined?(Rails.logger) && Rails.logger
          Rails.logger.error("Failed to load plugin from #{manifest_path}: #{e.message}")
        end
        # :nocov:
      end

      def find_latest_definition(plugin_dir, previous_ids)
        @registry.all.find { |d| d.root_path&.to_s == plugin_dir.to_s } ||
          @registry.all.reject { |d| previous_ids.include?(d.identifier) }.last
      end

      def configure_paths(definition)
        plugin_root = definition.root_path

        configure_migration_paths(plugin_root)
        configure_app_paths(definition, plugin_root)
        configure_asset_paths(plugin_root)
        configure_locale_paths(plugin_root)
        configure_view_paths(plugin_root)
      end

      def configure_migration_paths(plugin_root)
        migrations_dir = plugin_root.join("db", "migrate")
        # :nocov:
        @app_config.paths["db/migrate"] << migrations_dir.to_s if migrations_dir.exist?
        # :nocov:
      end

      def configure_app_paths(definition, plugin_root)
        app_dir = plugin_root.join("app")
        # :nocov:
        return unless app_dir.exist?
        # :nocov:

        configure_standard_app_paths(definition, app_dir)
        configure_rag_step_namespaced_paths(definition, app_dir)
        configure_connector_namespaced_paths(definition, app_dir)
        configure_capability_namespaced_paths(definition, app_dir)
        configure_tool_namespaced_paths(definition, app_dir)
        configure_channel_namespaced_paths(definition, app_dir)
      end

      def configure_standard_app_paths(definition, app_dir)
        ["models", "services", "controllers", "helpers", "jobs", "agents", "tools"].each do |subdir|
          path = app_dir.join(subdir)
          next unless path.exist? && !handled_by_custom_namespace_loader?(definition, subdir)

          @app_config.autoload_paths << path.to_s
          @app_config.eager_load_paths << path.to_s
        end
      end

      def configure_asset_paths(plugin_root)
        return unless @app_config.respond_to?(:assets) && @app_config.assets.respond_to?(:paths)

        assets_dir = plugin_root.join("app", "assets")
        if assets_dir.exist?
          asset_subdirectories = Dir.children(assets_dir).filter_map do |entry|
            path = assets_dir.join(entry)
            path.to_s if path.directory?
          end

          @app_config.assets.paths.concat(asset_subdirectories)
        end

        javascript_dir = plugin_root.join("app", "javascript")
        @app_config.assets.paths << javascript_dir.to_s if javascript_dir.exist?
      end

      def configure_locale_paths(plugin_root)
        locales_dir = plugin_root.join("config", "locales")
        @app_config.i18n.load_path += Dir[locales_dir.join("*.yml")] if locales_dir.exist?
      end

      def configure_view_paths(plugin_root)
        views_dir = plugin_root.join("app", "views")
        # :nocov:
        return unless views_dir.exist?
        # :nocov:

        @app_config.paths["app/views"] << views_dir.to_s
      end

      def handled_by_custom_namespace_loader?(definition, subdir)
        # Multi-category plugins use subdirectory convention — no custom namespace loading
        return false if multi_category_plugin?(definition)

        NAMESPACED_PLUGIN_SUBDIRS.any? { |pred, dirs| definition.public_send(pred) && dirs.include?(subdir) }
      end

      def multi_category_plugin?(definition)
        # Only count categories that push the whole app/models/ dir to a namespace.
        # Capabilities push a subdirectory (app/models/capabilities/) so they
        # can coexist with any single-namespace push without conflict.
        [
          definition.connector_plugin?,
          definition.tool_plugin?,
          definition.rag_step_plugin?,
        ].count(true) > 1
      end

      def configure_rag_step_namespaced_paths(definition, app_dir)
        return unless definition.rag_step_plugin?
        return if multi_category_plugin?(definition)

        configure_namespaced_path(app_dir.join("models"), ensure_namespace(:RagSteps))
        configure_namespaced_path(app_dir.join("services"), ensure_namespace(:Rag))
      end

      def configure_connector_namespaced_paths(definition, app_dir)
        return unless definition.connector_plugin?
        return if multi_category_plugin?(definition)

        configure_namespaced_path(app_dir.join("models"), ensure_namespace(:Connectors))
      end

      def configure_capability_namespaced_paths(definition, app_dir)
        return unless definition.capability_plugin?

        configure_namespaced_path(app_dir.join("models", "capabilities"), ensure_namespace(:Capabilities))
      end

      def configure_tool_namespaced_paths(definition, app_dir)
        return unless definition.only_tool_plugin?
        return if multi_category_plugin?(definition)

        configure_namespaced_path(app_dir.join("models"), ensure_namespace(:Tools))
        configure_namespaced_path(app_dir.join("services"), ensure_namespace(:Tools))
        configure_namespaced_path(app_dir.join("agents"), ensure_namespace(:Tools))
      end

      def configure_channel_namespaced_paths(definition, app_dir)
        return unless definition.channel_plugin?

        configure_namespaced_path(app_dir.join("models", "channels"), ensure_namespace(:Channels))
      end

      def configure_namespaced_path(path, namespace)
        # :nocov:
        return unless path.exist?
        # :nocov:

        Rails.autoloaders.main.push_dir(path.to_s, namespace:)
      end

      def ensure_namespace(name)
        return Object.const_get(name) if Object.const_defined?(name, false)

        Object.const_set(name, Module.new)
      end
    end
  end
end
