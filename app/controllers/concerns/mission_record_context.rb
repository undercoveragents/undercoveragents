# frozen_string_literal: true

module MissionRecordContext
  private

  def set_mission
    @mission = current_tenant.missions.includes(:operation).friendly.find(params.expect(:id))
    adopt_mission_operation!(@mission.operation)
  end

  def adopt_mission_operation!(operation)
    Operation.set_current_operation(session, operation)
    @current_operation = operation
    Current.operation = operation
  end
end
