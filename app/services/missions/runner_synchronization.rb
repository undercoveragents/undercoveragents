# frozen_string_literal: true

module Missions
  # Edge-state tracking and multi-input join synchronization for graph execution.
  module RunnerSynchronization
    include RunnerBranchPruning
    include RunnerEdgeState
    include RunnerJoinSynchronization
  end
end
