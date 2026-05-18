# frozen_string_literal: true

module TestSuites
  module AgentAlphaFixtureCleanup
    private

    def cleanup_fixture_records!
      fixture_channel_records = fixture_channels.to_a
      detach_fixture_chats!(fixture_channel_records)
      fixture_channel_records.each { |record| destroy_record(record) }
      destroy_operation_test_suites!
      destroy_collection(operation.tools)
      destroy_collection(operation.skill_catalogs)
      destroy_collection(operation.rag_flows)
      destroy_collection(operation.agents)
      destroy_collection(operation.missions)
      destroy_record(operation.reload)
    end

    def fixture_channels
      channel_ids = operation.channels.where("name LIKE ?", "#{case_record_prefix}%").pluck(:id)
      channel_ids.concat(channel_ids_for_operation_targets)

      operation.channels.where(id: channel_ids.uniq)
    end

    def channel_ids_for_operation_targets
      agent_channel_ids = ChannelTarget.where(
        target_type: "Agent",
        target_id: operation.agents.select(:id),
      ).pluck(:channel_id)
      mission_channel_ids = ChannelTarget.where(
        target_type: "Mission",
        target_id: operation.missions.select(:id),
      ).pluck(:channel_id)

      agent_channel_ids + mission_channel_ids
    end

    # rubocop:disable Rails/SkipsModelValidations
    def detach_fixture_chats!(channels)
      now = Time.current
      Chat.where(agent_id: operation.agents.select(:id)).update_all(agent_id: nil, updated_at: now)
      Chat.where(mission_id: operation.missions.select(:id)).update_all(mission_id: nil, updated_at: now)

      channel_ids = channels.map(&:id)
      return if channel_ids.empty?

      Chat.where(channel_id: channel_ids).update_all(channel_id: nil, updated_at: now)
      Chat.where(channel_target_id: ChannelTarget.where(channel_id: channel_ids).select(:id))
          .update_all(channel_target_id: nil, updated_at: now)
      Chat.where(channel_conversation_id: ChannelConversation.where(channel_id: channel_ids).select(:id))
          .update_all(channel_conversation_id: nil, updated_at: now)
    end
    # rubocop:enable Rails/SkipsModelValidations

    def destroy_operation_test_suites!
      TestSuite.where(agent_id: operation.agents.select(:id)).or(
        TestSuite.where(mission_id: operation.missions.select(:id)),
      ).find_each { |suite| destroy_record(suite) }
    end

    def destroy_collection(collection)
      collection.find_each { |record| destroy_record(record) }
    end

    def case_record_prefix
      render_context.fetch(:benchmark_operation_name).delete_suffix(" Operation")
    end

    def destroy_record(record)
      record&.destroy!
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
