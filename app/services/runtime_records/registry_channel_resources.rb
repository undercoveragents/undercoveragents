# frozen_string_literal: true

module RuntimeRecords
  module RegistryChannelResources
    private

    def register_channel
      register(
        "channel",
        label: "Channel",
        model_class: Channel,
        permitted_attributes: method(:channel_permitted_attributes),
        scope_resolver: method(:channel_scope),
        base_attributes: method(:channel_base_attributes),
        default_page: lambda do |record:, **|
          record&.client_channel? ? "preview" : "show"
        end,
        page_resolver: method(:channel_page_path),
        create_handler: method(:channel_create),
        update_handler: method(:channel_update),
      )
    end

    def channel_scope(context)
      Channel.where(operation: channel_operation(context))
    end

    def channel_base_attributes(context)
      operation = channel_operation(context)

      { operation:, tenant: operation.tenant }
    end

    def channel_page_path(page, record:, context:)
      _context = context
      return channel_collection_page_path(page) if ["index", "new"].include?(page.to_s)

      channel_member_page_path(page, record)
    end

    def channel_collection_page_path(page)
      path_helpers = {
        "index" => :admin_channels_path,
        "new" => :new_admin_channel_path,
      }

      Rails.application.routes.url_helpers.public_send(path_helpers.fetch(page.to_s))
    end

    def channel_member_page_path(page, record)
      raise ArgumentError, "Channel page '#{page}' requires a record." unless record

      helpers = Rails.application.routes.url_helpers

      case page.to_s
      when "show" then helpers.admin_channel_path(record)
      when "edit" then helpers.edit_admin_channel_path(record)
      when "preview"
        unless record.client_channel?
          raise ArgumentError, "Channel page 'preview' is only available for client channels."
        end

        helpers.admin_channel_path(record, view: :preview)
      else
        raise ArgumentError, "Unknown page '#{page}' for channel. Use index, new, show, edit, or preview."
      end
    end

    def channel_create(context:, definition:, attributes:, authorize:, **)
      channel_type = attributes["channel_type"].to_s.presence
      raise ArgumentError, "Channel create requires channel_type." if channel_type.blank?

      channel_attributes = definition.base_attributes_for(context).merge(base_channel_attributes(attributes))
      channel = definition.model_class.new(channel_attributes)
      channel.channel_type = channel_type
      apply_channel_configuration!(channel, configuration_channel_attributes(attributes))
      authorize.call(channel, :create?)

      channel.class.transaction do
        ensure_single_default_channel!(channel)
        channel.save!
        sync_channel_targets!(channel, attributes:, operation: channel_operation(context), creating: true)
        ensure_api_channel_credential!(channel)
      end

      channel
    end

    def channel_update(record:, attributes:, context:, **)
      requested_type = attributes["channel_type"].to_s.presence
      if requested_type.present? && requested_type != record.channel_type
        raise ArgumentError, "Channel type cannot be changed once the channel exists."
      end

      record.class.transaction do
        record.assign_attributes(base_channel_attributes(attributes.except("channel_type")))
        apply_channel_configuration!(record, configuration_channel_attributes(attributes))
        ensure_single_default_channel!(record)
        record.save!
        sync_channel_targets!(record, attributes:, operation: channel_operation(context), creating: false)
        ensure_api_channel_credential!(record)
      end

      record
    end

    def channel_operation(context)
      operation = context.operation
      raise ArgumentError, "No active operation is available for channels." unless operation

      operation
    end

    def apply_channel_configuration!(channel, attributes)
      attributes.each do |key, value|
        setter = "#{key}="
        next unless channel.respond_to?(setter)

        channel.public_send(setter, value)
      end
    end

    def sync_channel_targets!(channel, attributes:, operation:, creating:)
      return sync_api_channel_targets!(channel, attributes:, operation:, creating:) if channel.api_channel?

      return unless creating || single_target_attribute_updated?(attributes)

      sync_single_channel_target!(channel, resolve_single_channel_target(channel, attributes:, operation:))
    end

    def sync_client_channel_target!(channel, attributes:, operation:, creating:)
      return unless creating || attributes.key?("agent_id")

      sync_single_channel_target!(channel, resolve_channel_agent(attributes["agent_id"], operation:))
    end

    def single_target_attribute_updated?(attributes)
      ["target_kind", "agent_id", "mission_id"].any? { |key| attributes.key?(key) }
    end

    def resolve_single_channel_target(channel, attributes:, operation:)
      target_kind = attributes["target_kind"].to_s.presence || channel.allowed_target_kinds.first

      case target_kind
      when "agent"
        resolve_channel_agent(attributes["agent_id"], operation:)
      when "mission"
        resolve_channel_mission(attributes["mission_id"], operation:)
      end
    end

    def sync_api_channel_targets!(channel, attributes:, operation:, creating:)
      return unless sync_api_channel_targets?(channel, attributes:, creating:)

      sync_multiple_channel_targets!(channel, api_channel_target_records(channel, attributes:, operation:))
    end

    def sync_api_channel_targets?(channel, attributes:, creating:)
      return true if creating || channel.scope_all?

      ["access_scope", "agent_ids", "mission_ids"].any? { |key| attributes.key?(key) }
    end

    def api_channel_target_records(channel, attributes:, operation:)
      agent_ids = resolved_api_agent_ids(channel, attributes)
      mission_ids = resolved_api_mission_ids(channel, attributes, operation)

      operation.agents.enabled.selectable.where(id: agent_ids).order(:name).to_a +
        operation.missions.where(id: mission_ids).order(:name).to_a
    end

    def resolved_api_agent_ids(channel, attributes)
      return Array(attributes["agent_ids"]).compact_blank if attributes.key?("agent_ids")

      channel.channel_targets.where(target_type: "Agent").pluck(:target_id).map(&:to_s)
    end

    def resolved_api_mission_ids(channel, attributes, operation)
      return operation.missions.order(:name).pluck(:id).map(&:to_s) if channel.scope_all?
      return Array(attributes["mission_ids"]).compact_blank if attributes.key?("mission_ids")

      channel.channel_targets.where(target_type: "Mission").pluck(:target_id).map(&:to_s)
    end

    def sync_single_channel_target!(channel, record)
      return channel.channel_targets.destroy_all if record.nil?

      target = channel.channel_targets.find_or_initialize_by(target: record)
      target.position = 0
      target.default = true
      target.save!
      channel.channel_targets.where.not(id: target.id).destroy_all
    end

    def sync_multiple_channel_targets!(channel, records)
      target_ids = records.each_with_index.map do |record, index|
        target = channel.channel_targets.find_or_initialize_by(target: record)
        target.position = index
        target.default = index.zero?
        target.save!
        target.id
      end

      channel.channel_targets.where.not(id: target_ids).destroy_all
    end

    def resolve_channel_agent(agent_id, operation:)
      identifier = agent_id.to_s.strip
      return nil if identifier.blank?

      scope = operation.agents.enabled.selectable
      scope.find_by(id: identifier) || scope.find_by(slug: identifier)
    end

    def resolve_channel_mission(mission_id, operation:)
      identifier = mission_id.to_s.strip
      return nil if identifier.blank?

      operation.missions.find_by(id: identifier) || operation.missions.find_by(slug: identifier)
    end

    def ensure_api_channel_credential!(channel)
      return unless channel.api_channel?
      return if channel.channel_credentials.exists?

      channel.channel_credentials.create!(name: "Primary Token", credential_type: :bearer_token)
    end

    def ensure_single_default_channel!(channel)
      return unless channel.default?

      channel.class.where(operation: channel.operation, channel_type: channel.channel_type)
             .where.not(id: channel.id)
             .update_all(default: false) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
