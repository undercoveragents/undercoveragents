# frozen_string_literal: true

require "async"
require "timeout"

module Missions
  # The MissionRunner is the core queue-driven workflow execution engine.
  #
  # It snapshots a Mission flow definition, restores any persisted scheduler
  # frontiers, and drains branch-local work queues until the graph completes.
  # Focused runner modules own frontier restoration, edge dispatch, control-flow,
  # synchronization, node execution, and lifecycle transitions, while all mutable
  # state is persisted on MissionRun + ExecutionContext for inspect/pause/resume.
  #
  # ## Architecture
  #
  # - **Stateless per invocation**: the Runner reads/writes all state through
  #   the MissionRun record and an ExecutionContext. No instance state survives
  #   between calls.
  # - **Queue-driven graph execution**: branch-local RunnerScheduler instances
  #   drain ready work iteratively, and same-handle fan-out forks child
  #   schedulers that share the global execution counter.
  # - **Modular orchestration**: frontier seeding/resume lives in
  #   RunnerFrontierTraversal, edge routing in RunnerEdgeDispatch, work-item
  #   draining in RunnerTraversal, control-flow in the dedicated control modules,
  #   joins in RunnerSynchronization, node execution in RunnerNodeExecution,
  #   graph/context bootstrap in RunnerExecutionSetup, state writes/checkpoints
  #   in RunnerStatePersistence, and top-level run flow in RunnerLifecycle.
  # - **Variable system**: powered by ExecutionContext for expression evaluation.
  #   Variables are scoped per run and flow through the graph.
  # - **Resumable**: execution state, scheduler frontiers, and current position
  #   are persisted after each step, enabling pause/resume.
  # - **Isolated**: can be tested without Rails booted — only depends on
  #   the MissionRun model, FlowGraph, ExecutionContext, and node classes.
  #
  # ## Usage
  #
  #   runner = Missions::Runner.new(mission)
  #   run = runner.execute(variables: { "input" => "Hello" })
  #   run.completed?  # => true
  #   run.variables    # => { "output" => "..." }
  #
  #   # Resume a paused run
  #   runner.resume(run)
  #
  #   # Cancel a running run
  #   runner.cancel(run)
  #
  class Runner
    include RunnerConcurrency
    include RunnerControlFlow
    include RunnerEdgeDispatch
    include RunnerExecutionSetup
    include RunnerFrameCompatibility
    include RunnerFrontierTraversal
    include RunnerIteratorFlow
    include RunnerLifecycle
    include RunnerLoopFlow
    include RunnerNodeExecution
    include RunnerStatePersistence
    include RunnerSynchronization
    include RunnerTraversal

    # Maximum total node executions per run (guards against infinite graphs).
    MAX_TOTAL_EXECUTIONS = 10_000
    # Maximum iterations for a single loop/iterator node.
    MAX_LOOP_ITERATIONS = 1_000
    # Maximum time (seconds) a single node may run before being killed.
    NODE_EXECUTION_TIMEOUT = 120
    LOOP_PORT = "loop"
    ITERATOR_RUNTIME_KEYS = ["item", "index", "total"].freeze

    attr_reader :mission

    def initialize(mission)
      @mission = mission
    end

    # ── Public API ──

    # Starts a new execution of the mission.
    # Returns the MissionRun record (completed, failed, or paused).
    def execute(variables: {}, trigger_data: {})
      run = create_run(trigger_data:)
      execute_run(run, variables:, trigger_data:)
    end

    # Executes a pre-created run (used when the run is created by the controller
    # and execution is deferred to a background job).
    def resume_or_execute(run, variables: {}, trigger_data: {})
      execute_run(run, variables:, trigger_data:)
    end

    # Resumes a paused or interrupted run from its saved state.
    def resume(run)
      continue_saved_run(
        run,
        allowed_statuses: ["paused", "running"],
        invalid_message: "Cannot resume a #{run.status} run",
      )
    end

    # Cancels an active run.
    def cancel(run)
      return unless run.active?

      run.update!(status: :cancelled, completed_at: Time.current)
    end

    # Retries a failed run from the failed node.
    def retry_from_failure(run)
      continue_saved_run(
        run,
        allowed_statuses: ["failed"],
        invalid_message: "Can only retry failed runs",
        update_attrs: { error: nil },
      )
    end
  end
end
