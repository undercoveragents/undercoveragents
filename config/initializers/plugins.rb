# frozen_string_literal: true

# Sync plugin registry with database state and register step/connector/capability/tool types.
# Creates DB records for new plugins and marks missing ones disabled.
# Registers StepType and ConnectorType entries from plugin definitions (deferred
# from boot because they are not available during the config phase).
Rails.application.config.after_initialize do
  rake_tasks = defined?(Rake.application) ? Rake.application.top_level_tasks : []
  asset_task = rake_tasks.any? { |task| task.start_with?("assets:") }
  db_task = rake_tasks.any? { |task| task.start_with?("db:") }

  if defined?(UndercoverAgents::PluginSystem) && UndercoverAgents::PluginSystem.registry
    # Register step, connector, capability, and tool types now that Zeitwerk is ready
    UndercoverAgents::PluginSystem.register_step_types!
    UndercoverAgents::PluginSystem.register_connector_types!
    UndercoverAgents::PluginSystem.register_capability_types!
    UndercoverAgents::PluginSystem.register_tool_types!
    UndercoverAgents::PluginSystem.register_channel_types!

    next if asset_task || db_task

    begin
      UndercoverAgents::PluginSystem.registry.sync_with_database!
    rescue ActiveRecord::StatementInvalid => e
      # Database might not exist yet (during db:create / db:migrate)
      Rails.logger.warn("Plugin sync skipped: #{e.message}")
    end
  end
end

if Rails.env.development?
  plugin_root = Rails.root.join("plugins")

  if plugin_root.exist?
    plugin_manifest_reloader = ActiveSupport::FileUpdateChecker.new([], { plugin_root.to_s => ["rb"] }) do
      UndercoverAgents::PluginSystem.reload_manifests!(Rails.application.config, plugin_root)
    end

    Rails.application.reloaders << plugin_manifest_reloader

    Rails.application.reloader.to_prepare do
      plugin_manifest_reloader.execute_if_updated

      next unless defined?(UndercoverAgents::PluginSystem)

      if UndercoverAgents::PluginSystem.registry.empty?
        UndercoverAgents::PluginSystem.load!(Rails.application.config, plugin_root)
      end

      RagStepPlugin.reset!
      UndercoverAgents::PluginSystem.register_step_types!

      if defined?(ConnectorPlugin)
        ConnectorPlugin.reset!
        Connector.reset_sensitive_keys_cache! if defined?(Connector)
      end
      UndercoverAgents::PluginSystem.register_connector_types!

      CapabilityPlugin.reset! if defined?(CapabilityPlugin)
      UndercoverAgents::PluginSystem.register_capability_types!

      ToolPlugin.reset! if defined?(ToolPlugin)
      UndercoverAgents::PluginSystem.register_tool_types!

      ChannelPlugin.reset! if defined?(ChannelPlugin)
      UndercoverAgents::PluginSystem.register_channel_types!
    end
  end
end
