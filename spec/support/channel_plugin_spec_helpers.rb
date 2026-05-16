# frozen_string_literal: true

module ChannelPluginSpecHelpers
  CHANNEL_PLUGIN_REGISTRY_IVARS = [
    :@type_map,
    :@label_map,
    :@icon_map,
    :@description_map,
    :@source_map,
  ].freeze

  def with_mission_only_channel_type
    snapshot = snapshot_channel_plugin_registry

    stub_const("Channels::MissionOnlySpecChannel", build_mission_only_channel_class)
    register_mission_only_channel_type

    yield
  ensure
    restore_channel_plugin_registry(snapshot) if snapshot
  end

  private

  def snapshot_channel_plugin_registry
    ChannelPlugin.type_map

    CHANNEL_PLUGIN_REGISTRY_IVARS.index_with do |ivar|
      ChannelPlugin.instance_variable_get(ivar).dup
    end
  end

  def restore_channel_plugin_registry(snapshot)
    snapshot.each do |ivar, value|
      ChannelPlugin.instance_variable_set(ivar, value)
    end
  end

  def build_mission_only_channel_class
    Class.new do
      include UndercoverAgents::PluginSystem::Configurator
      include ChannelPlugin

      key "mission_only_spec"
      label "Mission Only"
      icon "fa-solid fa-vial"
      description "Spec-only single-target mission channel."
      target_kinds ["mission"]
    end
  end

  def register_mission_only_channel_type
    ChannelPlugin.register(
      "mission_only_spec",
      "Channels::MissionOnlySpecChannel",
      label: "Mission Only",
      icon: "fa-solid fa-vial",
      description: "Spec-only single-target mission channel.",
      source: :app,
    )
  end
end
