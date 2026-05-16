# frozen_string_literal: true

module Missions
  # Snapshot of a single node execution for the audit trail.
  NodeExecution = Data.define(
    :node_id,
    :node_type,
    :status,
    :input,
    :output,
    :next_port,
    :started_at,
    :finished_at,
    :error,
  ) do
    def initialize(
      node_id:,
      node_type:,
      status:,
      input: nil,
      output: nil,
      next_port: nil,
      started_at: nil,
      finished_at: nil,
      error: nil
    )
      super
    end
  end
end
