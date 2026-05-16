# frozen_string_literal: true

require "rails_helper"

RSpec.describe "UndercoverAgents::ActionCableThreadedExecutorCompat::ThreadedExecutorPatch" do
  describe ".apply!" do
    it "does not prepend the patch twice" do
      patch_count = lambda {
        ActionCable::Server::ThreadedExecutor.ancestors.count do |ancestor|
          ancestor == UndercoverAgents::ActionCableThreadedExecutorCompat::ThreadedExecutorPatch
        end
      }

      expect do
        UndercoverAgents::ActionCableThreadedExecutorCompat.apply!
      end.not_to change(&patch_count)
    end
  end

  describe "ActionCable::Server::ThreadedExecutor" do
    it "configures a bounded queue with caller-runs fallback" do
      executor = ActionCable::Server::ThreadedExecutor.new(max_size: 1)
      thread_pool = executor.instance_variable_get(:@executor)

      expect(thread_pool.max_queue).to eq(UndercoverAgents::ActionCableThreadedExecutorCompat::DEFAULT_MAX_QUEUE)
      expect(thread_pool.fallback_policy)
        .to eq(UndercoverAgents::ActionCableThreadedExecutorCompat::DEFAULT_FALLBACK_POLICY)
    end

    it "queues a second task instead of rejecting it when the worker is busy" do
      executor = ActionCable::Server::ThreadedExecutor.new(max_size: 1)
      started = Queue.new
      release = Queue.new
      completed = Queue.new

      executor.post do
        started << true
        release.pop
      end
      started.pop

      expect do
        executor.post { completed << true }
      end.not_to raise_error

      release << true
      expect(completed.pop).to be(true)
    ensure
      executor&.shutdown
    end

    it "runs the task inline after shutdown instead of raising" do
      executor = ActionCable::Server::ThreadedExecutor.new(max_size: 1)
      called = false

      executor.shutdown

      expect do
        executor.post { called = true }
      end.not_to raise_error
      expect(called).to be(true)
    end
  end
end
