# frozen_string_literal: true

module Missions
  # Raised when an output node completes execution, signalling that the
  # workflow should terminate immediately.  Carries the output variables
  # produced by the output node so they can be persisted on the run.
  class OutputReached < StandardError
    attr_reader :output_variables, :node_id

    def initialize(node_id:, output_variables: {})
      @node_id = node_id
      @output_variables = output_variables
      super("Output node '#{node_id}' reached — workflow complete")
    end
  end
end
