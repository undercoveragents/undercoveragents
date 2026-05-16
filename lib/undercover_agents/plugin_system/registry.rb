# frozen_string_literal: true

module UndercoverAgents
  module PluginSystem
    # In-memory registry of all loaded plugin definitions.
    # Provides query methods and database sync for enabled/disabled state.
    class Registry
      delegate :empty?, to: :@plugins
      def initialize
        @plugins = {}
        @enabled_state = {} # identifier => boolean (from DB)
      end

      def register(definition)
        @plugins[definition.identifier] = definition
      end

      def all
        @plugins.values
      end

      def find(identifier)
        @plugins[identifier.to_s]
      end

      def by_category(category)
        category_key = category.to_s
        @plugins.values.select do |plugin|
          Array(plugin.category).map(&:to_s).include?(category_key)
        end
      end

      def enabled
        @plugins.values.select { |p| enabled?(p.identifier) }
      end

      def disabled
        @plugins.values.reject { |p| enabled?(p.identifier) }
      end

      def enabled?(identifier)
        # Default to enabled if no DB record exists yet
        @enabled_state.fetch(identifier.to_s, true)
      end

      def count
        @plugins.size
      end

      def clear_definitions!
        @plugins = {}
      end

      # Syncs with the plugins database table.
      # Creates records for newly discovered plugins (enabled by default).
      # Loads enabled/disabled state from existing records.
      def sync_with_database!
        plugin_metadata = normalized_plugin_metadata
        existing = plugins_by_identifier(plugin_metadata.keys)
        insert_missing_plugins!(plugin_metadata.except(*existing.keys))
        existing = plugins_by_identifier(plugin_metadata.keys) if existing.size < plugin_metadata.size

        # Update metadata for existing plugins (only when changed) and cache enabled state.
        existing.each do |identifier, record|
          @enabled_state[identifier] = record.enabled?

          new_metadata = plugin_metadata[identifier]
          record.update!(metadata: new_metadata) unless new_metadata == record.metadata
        end
      end

      # Updates the enabled state (called when admin toggles a plugin)
      def set_enabled(identifier, enabled)
        @enabled_state[identifier.to_s] = enabled
      end

      private

      def plugins_by_identifier(identifiers)
        ::Plugin.where(identifier: identifiers).index_by(&:identifier)
      end

      def normalized_plugin_metadata
        @plugins.transform_values do |definition|
          JSON.parse(definition.to_h.except(:root_path).to_json)
        end
      end

      def insert_missing_plugins!(plugin_metadata)
        plugin_metadata.each do |identifier, metadata|
          create_missing_plugin!(identifier:, metadata:)
        end
      end

      def create_missing_plugin!(identifier:, metadata:)
        ::Plugin.new(identifier:, enabled: true, metadata:).save!
      rescue ActiveRecord::RecordInvalid => e
        raise unless duplicate_identifier_validation?(e, identifier)
      rescue ActiveRecord::RecordNotUnique
        # Another process inserted the same plugin between the existence check and save.
      end

      def duplicate_identifier_validation?(error, identifier)
        record = error.record

        record.is_a?(::Plugin) &&
          record.identifier.to_s == identifier.to_s &&
          record.errors.of_kind?(:identifier, :taken) &&
          record.errors.attribute_names == [:identifier]
      end
    end
  end
end
