# frozen_string_literal: true

module Missions
  RunnerFrame = Data.define(:run, :graph, :context, :scheduler)

  NodeExecutionRequest = Data.define(:run, :context, :node_id, :node_type, :node_data, :execution_count, :scheduler) do
    def self.from_frame(frame, node_details)
      new(
        run: frame.run,
        context: frame.context,
        node_id: node_details[:id],
        node_type: node_details[:type],
        node_data: node_details[:data],
        execution_count: frame.scheduler.execution_count,
        scheduler: frame.scheduler,
      )
    end
  end
end
