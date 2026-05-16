# frozen_string_literal: true

module Missions
  # Immutable result returned by every node's #execute method.
  NodeResult = Data.define(:status, :output, :next_port, :variables) do
    def initialize(status:, output: nil, next_port: "default", variables: {})
      super(status: status.to_sym, output:, next_port: next_port.to_s, variables:)
    end

    def success?
      status == :success
    end

    def failure?
      status == :failure
    end

    def skip?
      status == :skip
    end
  end
end
