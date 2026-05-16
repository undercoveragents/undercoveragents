# frozen_string_literal: true

module MissionDesigner
  # Triggers an automatic layout rearrangement of the mission flow canvas.
  # Broadcasts a signal to the frontend to run ELK-based auto-arrange.
  # Call this after adding and connecting nodes to keep the canvas tidy.
  class ArrangeFlowTool < BaseTool
    description "Auto-arranges the canvas. Call after each add-and-connect cycle."

    def initialize(mission, runtime_context: nil)
      super
    end

    def name
      "arrange_flow"
    end

    def execute
      authorize_mission_update!(mission)
      Turbo::StreamsChannel.broadcast_append_to(
        "mission_flow_#{mission.id}",
        target: "mission-flow-updates",
        html: "<div data-arrange=\"true\"></div>",
      )
      "Flow arranged. Nodes have been repositioned with an automatic layout."
    rescue Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error arranging flow: #{e.message}"
    end
  end
end
