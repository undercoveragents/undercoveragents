# frozen_string_literal: true

module RuntimeRecords
  module RegistryChannelAttributes
    private

    def base_channel_attributes(attributes)
      attributes.slice("name", "description", "enabled", "default", "connector_id")
    end

    def configuration_channel_attributes(attributes)
      attributes.except(
        "name",
        "description",
        "enabled",
        "default",
        "connector_id",
        "channel_type",
        "target_kind",
        "agent_id",
        "agent_ids",
        "mission_id",
        "mission_ids",
      )
    end

    def channel_permitted_attributes
      RuntimeRecords::CHANNEL_PERMITTED_ATTRIBUTES + channel_plugin_attribute_keys
    end

    def channel_plugin_attribute_keys
      ChannelPlugin.type_keys.flat_map do |type_key|
        klass = ChannelPlugin.resolve(type_key)
        next [] unless klass.respond_to?(:attribute_types)

        klass.attribute_types.keys
      end.uniq
    end
  end
end
