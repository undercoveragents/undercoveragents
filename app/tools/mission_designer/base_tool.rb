# frozen_string_literal: true

module MissionDesigner
  class BaseTool < RubyLLM::Tool
    include PolicyAuthorizable

    attr_reader :mission, :mission_resolver, :runtime_context

    def initialize(mission = nil, runtime_context: nil)
      super()
      @mission = mission || runtime_context&.mission
      @runtime_context = runtime_context
      @mission_resolver = MissionDesigner::TargetMissionResolver.new(
        fallback_mission: @mission,
        runtime_context:,
      )
    end

    private

    def resolve_target_mission(mission_id = nil, missing_message: nil)
      return mission_resolver.resolve(mission_id) if mission_id.present? || mission.present?
      raise ArgumentError, missing_message if missing_message

      mission_resolver.resolve(mission_id)
    end

    def authorize_mission_read!(target_mission)
      return if policy_user.blank?

      authorize_policy!(target_mission, :show?, user: policy_user)
    end

    def authorize_mission_update!(target_mission)
      return if policy_user.blank?

      authorize_policy!(target_mission, :update?, user: policy_user)
    end

    def policy_user
      runtime_context&.user || Current.user
    end
  end
end
