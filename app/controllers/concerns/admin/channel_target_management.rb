# frozen_string_literal: true

module Admin
  module ChannelTargetManagement
    extend ActiveSupport::Concern

    private

    def ensure_single_default_channel
      return unless @channel.default?

      current_tenant.channels.where(channel_type: @channel.channel_type, default: true)
                    .where.not(id: @channel.id)
                    .find_each { |channel| channel.update!(default: false) }
    end

    def sync_targets!
      return sync_api_targets! if @channel.api_channel?

      sync_single_target!(target_record: selected_target_record)
    end

    def sync_single_target!(target_record:)
      @channel.channel_targets.destroy_all
      return unless target_record

      @channel.channel_targets.create!(target: target_record, default: true, position: 0)
    end

    def upsert_default_target!
      target_record = selected_target_record
      return unless target_record

      channel_target = @channel.channel_targets.find_or_initialize_by(default: true)
      channel_target.target = target_record
      channel_target.position = 0
      channel_target.save!
      demote_other_default_targets!(channel_target)
    end

    def demote_other_default_targets!(channel_target)
      @channel.channel_targets.where.not(id: channel_target.id).find_each do |target|
        target.update!(default: false)
      end
    end

    def selected_target_record
      case target_params[:target_kind]
      when "agent" then selected_agent_record
      when "mission" then selected_mission_record
      end
    end

    def selected_agent_record
      scoped_agents.find_by(id: target_params[:agent_id])
    end

    def selected_mission_record
      scoped_missions.find_by(id: target_params[:mission_id])
    end

    def target_params
      @target_params ||= params.fetch(:channel_target, ActionController::Parameters.new)
                               .permit(:target_kind, :agent_id, :mission_id, agent_ids: [], mission_ids: [])
    end

    def load_form_data
      @connectors = scoped_connectors.enabled.ordered
      @available_agents = current_tenant.agents.enabled.selectable.ordered
      @available_missions = current_tenant.missions.ordered
      load_selected_target
    end

    def load_selected_target
      default_target = default_target_record
      @selected_target_kind = selected_target_kind(default_target)
      @selected_agent_id = target_params[:agent_id].presence || default_target_agent_id(default_target)
      @selected_mission_id = target_params[:mission_id].presence || default_target_mission_id(default_target)
      @selected_agent_ids = Array(target_params[:agent_ids]).presence || selected_target_ids("Agent")
      @selected_mission_ids = Array(target_params[:mission_ids]).presence || selected_target_ids("Mission")
    end

    def default_target_record
      @channel.default_target
    end

    def selected_target_kind(default_target)
      target_params[:target_kind].presence || default_target&.target_kind || @channel.allowed_target_kinds.first
    end

    def default_target_agent_id(default_target)
      default_target.target_id if default_target&.target_type == "Agent"
    end

    def default_target_mission_id(default_target)
      default_target.target_id if default_target&.target_type == "Mission"
    end

    def selected_target_ids(target_type)
      @channel.channel_targets
              .select { |target| target.target_type == target_type }
              .map { |target| target.target_id.to_s }
    end

    def sync_api_targets!
      records = []
      records.concat(selected_api_agents)
      records.concat(selected_api_missions)

      persisted_target_ids = records.each_with_index.map do |target_record, index|
        persist_api_target!(target_record, index)
      end

      @channel.channel_targets.where.not(id: persisted_target_ids).destroy_all
    end

    def persist_api_target!(target_record, index)
      target = @channel.channel_targets.find_or_initialize_by(target: target_record)
      target.position = index
      target.default = index.zero?
      target.save!
      target.id
    end

    def selected_api_agents
      ids = Array(target_params[:agent_ids]).compact_blank
      return [] if ids.empty?

      current_tenant.agents.enabled.selectable.where(id: ids).order(:name).to_a
    end

    def selected_api_missions
      scope = current_tenant.missions
      return scope.ordered.to_a if @channel.scope_all?

      ids = Array(target_params[:mission_ids]).compact_blank
      return [] if ids.empty?

      scope.where(id: ids).order(:name).to_a
    end
  end
end
