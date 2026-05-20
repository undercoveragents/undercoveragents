# frozen_string_literal: true

require_relative "plugin_system/definition"
require_relative "plugin_system/registry"
require_relative "plugin_system/loader"
require_relative "plugin_system/configurator"

module UndercoverAgents
  # Central plugin system for Undercover Agents.
  # Discovers, loads, and manages plugins from the plugins/ directory.
  # Each plugin is a self-contained directory with a plugin.rb manifest
  # that registers metadata and a lightweight Rails Engine for autoloading.
  module PluginSystem # rubocop:disable Metrics/ModuleLength
    class Error < StandardError; end

    class << self # rubocop:disable Metrics/ClassLength
      # Returns the global plugin registry
      def registry
        @registry ||= Registry.new
      end

      # Discovers and loads all plugins from the given path.
      # Called during Rails boot in config/application.rb.
      def load!(app_config, plugins_path)
        Loader.new(app_config, plugins_path, registry).load_all!
      end

      # Reloads plugin manifests at runtime (development), rebuilding registry
      # metadata and RagStepPlugin registrations without mutating loader paths.
      def reload_manifests!(app_config, plugins_path)
        registry.clear_definitions!
        # :nocov:
        RagStepPlugin.reset! if defined?(RagStepPlugin)
        ConnectorPlugin.reset! if defined?(ConnectorPlugin)
        CapabilityPlugin.reset! if defined?(CapabilityPlugin)
        ToolPlugin.reset! if defined?(ToolPlugin)
        ChannelPlugin.reset! if defined?(ChannelPlugin)
        WebSearch::SearchClientRegistry.reset! if defined?(WebSearch::SearchClientRegistry)
        # :nocov:

        Loader.new(app_config, plugins_path, registry).load_all!(configure_paths: false)
        register_step_types!
        register_connector_types!
        register_capability_types!
        register_tool_types!
        register_channel_types!
        sync_database!
      end

      # Syncs the registry with the database (creates Plugin AR records for
      # newly discovered plugins, preserves enabled/disabled state).
      # Called in an initializer after ActiveRecord is available.
      def sync_database!
        return unless defined?(::Plugin) && ::Plugin.table_exists?

        registry.sync_with_database!
      end

      # Registers RagStepPlugin entries for all rag_step plugins.
      # Must be called after Zeitwerk is ready (after_initialize).
      def register_step_types!
        registry.all.to_a.each do |definition|
          entry_points = definition.rag_step_entry_points
          next if entry_points.empty?

          entry_points.each do |entry|
            class_name = normalize_entry_point_class_name(entry.fetch(:class_name))
            metadata = step_plugin_metadata_for(
              definition:,
              entry:,
              class_name:,
              total_entry_points: entry_points.size,
            )

            RagStepPlugin.register(
              metadata.fetch(:key),
              class_name,
              label: metadata.fetch(:label),
              icon: metadata.fetch(:icon),
              stage: metadata.fetch(:stage),
            )
          end
        end
      end

      # Registers ConnectorPlugin entries for all connector plugins.
      # Must be called after Zeitwerk is ready (after_initialize).
      def register_connector_types!
        # :nocov:
        return unless defined?(ConnectorPlugin)
        # :nocov:

        ConnectorPlugin.register_core_types!

        registry.all.to_a.each do |definition|
          entry_points = definition.connector_entry_points
          next if entry_points.empty?

          entry_points.each do |entry|
            class_name = normalize_connector_class_name(entry.fetch(:class_name))
            metadata = connector_plugin_metadata_for(
              definition:,
              class_name:,
            )

            ConnectorPlugin.register(
              metadata.fetch(:key),
              class_name,
              label: metadata.fetch(:label),
              icon: metadata.fetch(:icon),
              description: metadata.fetch(:description),
            )
          end
        end
      end

      # Registers CapabilityPlugin entries for all capability plugins.
      # Must be called after Zeitwerk is ready (after_initialize).
      def register_capability_types!
        # :nocov:
        return unless defined?(CapabilityPlugin)
        # :nocov:

        registry.all.to_a.each do |definition|
          entry_points = definition.capability_entry_points
          next if entry_points.empty?

          entry_points.each do |entry|
            class_name = normalize_capability_class_name(entry.fetch(:class_name))
            metadata = capability_plugin_metadata_for(
              definition:,
              class_name:,
            )

            CapabilityPlugin.register(
              metadata.fetch(:key),
              class_name,
              label: metadata.fetch(:label),
              icon: metadata.fetch(:icon),
              description: metadata.fetch(:description),
            )
          end
        end
      end

      # Registers ToolPlugin entries for all tool plugins.
      # Must be called after Zeitwerk is ready (after_initialize).
      def register_tool_types!
        # :nocov:
        return unless defined?(ToolPlugin)
        # :nocov:

        registry.all.to_a.each do |definition|
          entry_points = definition.tool_entry_points
          next if entry_points.empty?

          entry_points.each do |entry|
            class_name = normalize_tool_class_name(entry.fetch(:class_name))
            metadata = tool_plugin_metadata_for(
              definition:,
              class_name:,
            )

            ToolPlugin.register(
              metadata.fetch(:key),
              class_name,
              label: metadata.fetch(:label),
              icon: metadata.fetch(:icon),
              description: metadata.fetch(:description),
            )
          end
        end
      end

      def register_channel_types!
        # :nocov:
        return unless defined?(ChannelPlugin)
        # :nocov:

        ChannelPlugin.register_core_types!

        registry.all.to_a.each do |definition|
          entry_points = definition.channel_entry_points
          next if entry_points.empty?

          entry_points.each do |entry|
            class_name = normalize_channel_class_name(entry.fetch(:class_name))
            metadata = channel_plugin_metadata_for(
              definition:,
              class_name:,
            )

            ChannelPlugin.register(
              metadata.fetch(:key),
              class_name,
              label: metadata.fetch(:label),
              icon: metadata.fetch(:icon),
              description: metadata.fetch(:description),
            )
          end
        end
      end

      # Resets the registry (useful for testing)
      def reset!
        @registry = Registry.new
      end

      # DSL entry point used by plugin.rb manifests
      def register(identifier, &block)
        definition = Definition.new(identifier)
        if block
          if block.arity == 1
            yield(definition)
          else
            definition.instance_eval(&block)
          end
        end
        definition.freeze!
        registry.register(definition)
        definition
      end

      private

      def step_plugin_metadata_for(definition:, entry:, class_name:, total_entry_points:)
        stage = step_stage_for(class_name:, entry:)
        resolved_key = step_key_for(definition:, entry:, class_name:, total_entry_points:)

        {
          key: resolved_key,
          label: step_label_for(class_name:, key: resolved_key),
          icon: step_icon_for(class_name:),
          stage:,
        }
      end

      def step_stage_for(class_name:, entry:)
        klass_stage_for(class_name.constantize) || entry.fetch(:stage)
      rescue NameError
        entry.fetch(:stage)
      end

      def step_key_for(definition:, entry:, class_name:, total_entry_points:)
        klass_key_for(class_name.constantize) || fallback_step_key(definition:, entry:, total_entry_points:)
      rescue NameError
        fallback_step_key(definition:, entry:, total_entry_points:)
      end

      def step_label_for(class_name:, key:)
        klass_label_for(class_name.constantize) || fallback_step_label(key)
      rescue NameError
        fallback_step_label(key)
      end

      def step_icon_for(class_name:)
        klass_icon_for(class_name.constantize) || "fa-solid fa-puzzle-piece"
      rescue NameError
        "fa-solid fa-puzzle-piece"
      end

      def klass_key_for(klass)
        return klass.key.to_s.presence if klass.respond_to?(:key)
        return klass.type_key.to_s.presence if klass.respond_to?(:type_key)

        nil
      end

      def klass_label_for(klass)
        return klass.label.presence if klass.respond_to?(:label)
        return klass.type_label.presence if klass.respond_to?(:type_label)

        nil
      end

      def klass_icon_for(klass)
        return klass.icon.presence if klass.respond_to?(:icon)
        return klass.type_icon.presence if klass.respond_to?(:type_icon)

        nil
      end

      def klass_stage_for(klass)
        return klass.stage if klass.respond_to?(:stage)

        nil
      end

      def fallback_step_key(definition:, entry:, total_entry_points:)
        return definition.identifier if total_entry_points == 1

        "#{definition.identifier}_#{entry.fetch(:stage)}"
      end

      def fallback_step_label(key)
        key.to_s.tr("_", " ").titleize
      end

      def normalize_entry_point_class_name(class_name)
        raw = class_name.to_s
        return raw if raw.include?("::")

        "RagSteps::#{raw}"
      end

      def normalize_connector_class_name(class_name)
        raw = class_name.to_s
        return raw if raw.include?("::")

        "Connectors::#{raw}"
      end

      def normalize_capability_class_name(class_name)
        raw = class_name.to_s
        return raw if raw.include?("::")

        "Capabilities::#{raw}"
      end

      def normalize_tool_class_name(class_name)
        raw = class_name.to_s
        return raw if raw.include?("::")

        "Tools::#{raw}"
      end

      def normalize_channel_class_name(class_name)
        raw = class_name.to_s
        return raw if raw.include?("::")

        "Channels::#{raw}"
      end

      def connector_plugin_metadata_for(definition:, class_name:)
        {
          key: connector_key_for(definition:, class_name:),
          label: connector_label_for(class_name:, definition:),
          icon: connector_icon_for(class_name:, definition:),
          description: connector_description_for(class_name:, definition:),
        }
      end

      def capability_plugin_metadata_for(definition:, class_name:)
        {
          key: capability_key_for(definition:, class_name:),
          label: capability_label_for(class_name:, definition:),
          icon: capability_icon_for(class_name:, definition:),
          description: capability_description_for(class_name:, definition:),
        }
      end

      def tool_plugin_metadata_for(definition:, class_name:)
        {
          key: tool_key_for(definition:, class_name:),
          label: tool_label_for(class_name:, definition:),
          icon: tool_icon_for(class_name:, definition:),
          description: tool_description_for(class_name:, definition:),
        }
      end

      def channel_plugin_metadata_for(definition:, class_name:)
        {
          key: channel_key_for(definition:, class_name:),
          label: channel_label_for(class_name:, definition:),
          icon: channel_icon_for(class_name:, definition:),
          description: channel_description_for(class_name:, definition:),
        }
      end

      def connector_key_for(definition:, class_name:)
        klass_key_for(class_name.constantize) || definition.identifier.delete_prefix("connector_")
      rescue NameError
        definition.identifier.delete_prefix("connector_")
      end

      def connector_label_for(class_name:, definition:)
        klass_label_for(class_name.constantize) || definition.name
      rescue NameError
        definition.name
      end

      def connector_icon_for(class_name:, definition:)
        klass_icon_for(class_name.constantize) || definition.icon
      rescue NameError
        definition.icon
      end

      def connector_description_for(class_name:, definition:)
        klass = class_name.constantize
        return klass.description.presence if klass.respond_to?(:description)

        definition.description
      rescue NameError
        definition.description
      end

      def capability_key_for(definition:, class_name:)
        klass_key_for(class_name.constantize) || definition.identifier.delete_prefix("capability_")
      rescue NameError
        definition.identifier.delete_prefix("capability_")
      end

      def capability_label_for(class_name:, definition:)
        klass_label_for(class_name.constantize) || definition.name
      rescue NameError
        definition.name
      end

      def capability_icon_for(class_name:, definition:)
        klass_icon_for(class_name.constantize) || definition.icon
      rescue NameError
        definition.icon
      end

      def capability_description_for(class_name:, definition:)
        klass = class_name.constantize
        return klass.description.presence if klass.respond_to?(:description)

        definition.description
      rescue NameError
        definition.description
      end

      def tool_key_for(definition:, class_name:)
        klass_key_for(class_name.constantize) || definition.identifier.delete_prefix("tool_")
      rescue NameError
        definition.identifier.delete_prefix("tool_")
      end

      def tool_label_for(class_name:, definition:)
        klass_label_for(class_name.constantize) || definition.name
      rescue NameError
        definition.name
      end

      def tool_icon_for(class_name:, definition:)
        klass_icon_for(class_name.constantize) || definition.icon
      rescue NameError
        definition.icon
      end

      def tool_description_for(class_name:, definition:)
        klass = class_name.constantize
        return klass.description.presence if klass.respond_to?(:description)

        definition.description
      rescue NameError
        definition.description
      end

      def channel_key_for(definition:, class_name:)
        klass_key_for(class_name.constantize) || definition.identifier.delete_prefix("channel_")
      rescue NameError
        definition.identifier.delete_prefix("channel_")
      end

      def channel_label_for(class_name:, definition:)
        klass_label_for(class_name.constantize) || definition.name
      rescue NameError
        definition.name
      end

      def channel_icon_for(class_name:, definition:)
        klass_icon_for(class_name.constantize) || definition.icon
      rescue NameError
        definition.icon
      end

      def channel_description_for(class_name:, definition:)
        klass = class_name.constantize
        return klass.description.presence if klass.respond_to?(:description)

        definition.description
      rescue NameError
        definition.description
      end
    end
  end
end
