# frozen_string_literal: true

require "action_cable/server/base"

module UndercoverAgents
  module ActionCableThreadedExecutorCompat
    DEFAULT_MAX_QUEUE = 256
    DEFAULT_FALLBACK_POLICY = :caller_runs

    module ThreadedExecutorPatch
      def initialize(
        max_size: 10,
        max_queue: UndercoverAgents::ActionCableThreadedExecutorCompat::DEFAULT_MAX_QUEUE,
        fallback_policy: UndercoverAgents::ActionCableThreadedExecutorCompat::DEFAULT_FALLBACK_POLICY,
        **_options
      )
        @executor = Concurrent::ThreadPoolExecutor.new(
          name: "ActionCable-streamer",
          min_threads: 1,
          max_threads: max_size,
          max_queue:,
          fallback_policy:,
        )
      end
    end

    def self.apply!
      return if ActionCable::Server::ThreadedExecutor < ThreadedExecutorPatch

      ActionCable::Server::ThreadedExecutor.prepend(ThreadedExecutorPatch)
    end
  end
end

UndercoverAgents::ActionCableThreadedExecutorCompat.apply!
