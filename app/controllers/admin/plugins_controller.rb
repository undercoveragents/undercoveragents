# frozen_string_literal: true

module Admin
  class PluginsController < BaseController
    def index
      @plugins = UndercoverAgents::PluginSystem.registry.all.sort_by { |plugin| plugin.name.to_s.downcase }
    end

    def toggle
      identifier = params[:id]
      plugin_def = UndercoverAgents::PluginSystem.registry.find(identifier)
      raise ActiveRecord::RecordNotFound, "Plugin not found: #{identifier}" unless plugin_def

      plugin_record = Plugin.find_or_create_by!(identifier:)
      plugin_record.update!(enabled: !plugin_record.enabled)
      UndercoverAgents::PluginSystem.registry.sync_with_database!

      status = plugin_record.enabled ? "enabled" : "disabled"
      redirect_to admin_plugins_path,
                  notice: "Plugin \"#{plugin_def.name}\" has been #{status}."
    end
  end
end
