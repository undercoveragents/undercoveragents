# frozen_string_literal: true

module Missions
  # Thread-safe mutable counter shared across concurrent traversal branches.
  class ExecutionCounter
    attr_reader :value

    def initialize(value: 0)
      @value = value.to_i
      @mutex = Mutex.new
    end

    def increment
      @mutex.synchronize { @value += 1 }
    end
  end
end
