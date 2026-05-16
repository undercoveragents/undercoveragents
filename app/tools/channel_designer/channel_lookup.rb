# frozen_string_literal: true

module ChannelDesigner
  module ChannelLookup
    private

    def resolve_channel(channel_id)
      return @current_channel if channel_id.blank? && @current_channel.is_a?(Channel)

      identifier = channel_id.to_s.strip
      return nil if identifier.blank?

      scope = Channel.where(tenant:)

      scope.find_by(id: identifier) || scope.find_by(slug: identifier) || unique_name_match(scope, identifier) ||
        missing_channel!(identifier)
    end

    def unique_name_match(scope, identifier)
      scope.find_by("LOWER(channels.name) = ?", identifier.downcase)
    end

    def missing_channel_message
      "No current channel is available. Open a channel page or pass channel_id."
    end

    def missing_channel!(identifier)
      raise ActiveRecord::RecordNotFound, "Channel '#{identifier}' was not found."
    end

    def tenant
      @runtime_context&.tenant || @current_channel&.tenant || Current.tenant || Tenant.default_tenant
    end
  end
end
