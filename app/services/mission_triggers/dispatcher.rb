# frozen_string_literal: true

module MissionTriggers
  class Dispatcher < AutomationTriggers::Dispatcher
    def initialize(mission_trigger:, source:, payload: {})
      super(automation_trigger: mission_trigger, source:, payload:)
    end

    private

    def trigger_metadata
      super.merge("mission_trigger_id" => automation_trigger.id)
    end
  end
end
