# frozen_string_literal: true

module Rag
  # Orchestrates the execution of an RAG.
  # Runs the 4 fixed stages in order: source → chunking → embedding → storage.
  # Uses batch processing to avoid memory explosion on large datasets:
  # the source step yields document batches via cursor-based iteration,
  # and each batch flows through the remaining stages before the next batch loads.
  class PipelineExecutor
    class ExecutionError < StandardError; end
    class CancelledError < StandardError; end
    StepExecution = Data.define(:steppable, :step_run, :stage, :batch, :context, :stats)

    STAGE_ORDER = [:source, :chunking, :embedding, :storage].freeze
    STEP_RUN_COUNT_FIELDS = {
      source: { output_count: :documents_loaded },
      chunking: { input_count: :documents_loaded, output_count: :chunks_created },
      embedding: { input_count: :chunks_created, output_count: :embeddings_generated },
      storage: { input_count: :documents_loaded, output_count: :documents_stored },
    }.freeze
    STAGE_ACCUMULATORS = {
      chunking: ->(documents) { documents.sum { |doc| doc.chunks.length } },
      embedding: ->(documents) { documents.sum { |doc| doc.chunks.count { |chunk| chunk.embedding.present? } } },
      storage: ->(documents) { documents.length },
    }.freeze

    def self.call(rag_flow, triggered_by: "manual", run: nil)
      new(rag_flow, triggered_by:, run:).call
    end

    def initialize(rag_flow, triggered_by: "manual", run: nil)
      @flow = rag_flow
      @triggered_by = triggered_by
      @existing_run = run
    end

    def call
      run = @existing_run || create_run

      begin
        run.update!(status: :running, started_at: Time.current)
        execute_pipeline(run)
        complete_run(run)
      rescue CancelledError
        cancel_run(run)
      rescue StandardError => e
        fail_run(run, e)
        raise
      end

      run
    end

    private

    def create_run
      @flow.rag_runs.create!(
        status: :pending,
        triggered_by: @triggered_by,
        stats: {},
      )
    end

    def execute_pipeline(run)
      source = @flow.module_for(:source)
      raise ExecutionError, "Source step is not configured" unless source

      step_runs = create_step_runs(run)
      context = build_context(run)
      stats = Hash.new(0)
      step_runs[:source].update!(status: :running, started_at: Time.current)
      broadcast_all_step_runs(run, step_runs, stats)

      run_source(source, run, step_runs, context, stats)
      finalize_remaining_step_runs(step_runs, stats)
    end

    def run_source(source, run, step_runs, context, stats)
      source.each_batch(context) do |batch|
        check_for_cancellation!(run)
        stats[:documents_loaded] += batch.length
        broadcast_step_run_progress(step_runs[:source], stats, :source)

        batch = filter_unchanged_documents(batch, stats)

        if batch.any?
          batch = run_stage(:chunking, step_runs, batch, context, stats)
          batch = run_stage(:embedding, step_runs, batch, context, stats)
          run_stage(:storage, step_runs, batch, context, stats)
        end

        broadcast_run_progress(run, stats)
      end
      finalize_step_run(step_runs[:source], :completed, stats, :source)
    rescue CancelledError
      raise
    rescue StandardError => e
      finalize_step_run(step_runs[:source], :failed, stats, :source, error: e)
      stage_config = RagFlow.stage_config(:source)
      raise ExecutionError, "Step '#{stage_config[:label]}' failed: #{e.message}"
    end

    def finalize_remaining_step_runs(step_runs, stats)
      STAGE_ORDER[1..].each do |stage|
        sr = step_runs[stage]
        next unless sr.running?

        finalize_step_run(sr, :completed, stats, stage)
      end
    end

    def run_stage(stage, step_runs, batch, context, stats)
      steppable = @flow.module_for(stage)
      step_run = step_runs[stage]

      return skip_stage(step_run, batch) unless steppable

      mark_step_running(step_run)
      execute_step(StepExecution.new(steppable:, step_run:, stage:, batch:, context:, stats:))
    end

    def skip_stage(step_run, batch)
      step_run.update!(status: :skipped) unless step_run.skipped?
      step_run.broadcast_progress
      batch
    end

    def mark_step_running(step_run)
      return unless step_run.pending?

      step_run.update!(status: :running, started_at: Time.current)
      step_run.broadcast_progress
    end

    def execute_step(execution)
      result = execution.steppable.execute(execution.batch, execution.context)
      accumulate_stats(execution.stats, execution.stage, result)
      broadcast_step_run_progress(execution.step_run, execution.stats, execution.stage)
      result
    rescue CancelledError
      raise
    rescue StandardError => e
      finalize_step_run(execution.step_run, :failed, execution.stats, execution.stage, error: e)
      stage_config = RagFlow.stage_config(execution.stage)
      raise ExecutionError, "Step '#{stage_config[:label]}' failed: #{e.message}"
    end

    def create_step_runs(run)
      STAGE_ORDER.each_with_index.with_object({}) do |(stage, index), hash|
        hash[stage] = run.rag_step_runs.create!(
          step_type: stage.to_s,
          position: index + 1,
          status: :pending,
        )
      end
    end

    def finalize_step_run(step_run, status, stats, stage, error: nil)
      attrs = { status:, completed_at: Time.current }
      attrs[:error_message] = error.message.truncate(1000) if error
      attrs[:stats] = build_step_stats(stage, stats)

      STEP_RUN_COUNT_FIELDS.fetch(stage, {}).each do |attr, stat_key|
        attrs[attr] = stats[stat_key]
      end

      step_run.update!(attrs)
      step_run.broadcast_progress
    end

    def accumulate_stats(stats, stage, documents)
      accumulator = STAGE_ACCUMULATORS[stage]
      return unless accumulator

      stat_key = STEP_RUN_COUNT_FIELDS.fetch(stage).fetch(:output_count)
      stats[stat_key] += accumulator.call(documents)
    end

    def build_step_stats(stage, stats)
      case stage
      when :source
        { "documents_loaded" => stats[:documents_loaded], "documents_skipped" => stats[:documents_skipped] }
      when :chunking then { "chunks_created" => stats[:chunks_created] }
      when :embedding then { "embeddings_generated" => stats[:embeddings_generated] }
      when :storage then { "documents_stored" => stats[:documents_stored] }
      else
        # :nocov:
        {}
        # :nocov:
      end
    end

    def build_context(run)
      { run_id: run.id, flow_id: @flow.id }
    end

    def check_for_cancellation!(run)
      run.reload
      raise CancelledError, "Run was cancelled" if run.cancelled?
    end

    # ── Document Deduplication ──────────────────────────────────────

    def filter_unchanged_documents(batch, stats)
      storage = deduplication_storage
      return batch unless storage

      hashes = batch.map(&:content_hash)
      existing = storage.existing_content_hashes(hashes)
      return batch if existing.empty?

      changed = batch.reject { |doc| existing.include?(doc.content_hash) }
      stats[:documents_skipped] += batch.length - changed.length
      changed
    rescue StandardError
      # If storage is unreachable or hash lookup fails, proceed without dedup
      batch
    end

    def deduplication_storage
      storage = @flow.module_for(:storage)
      return unless storage.respond_to?(:existing_content_hashes)
      # :nocov:
      return unless storage.respond_to?(:deduplication_applicable?) && storage.deduplication_applicable?
      # :nocov:

      storage
    end

    # ── Real-Time Broadcasts ────────────────────────────────────────

    def broadcast_step_run_progress(step_run, stats, stage)
      step_run.update_columns( # rubocop:disable Rails/SkipsModelValidations
        stats: build_step_stats(stage, stats),
        output_count: step_output_count(stage, stats),
        input_count: step_input_count(stage, stats),
      )
    end

    def broadcast_run_progress(run, stats)
      # Include updated_at as a heartbeat so stale detection can identify crashed runs.
      run.update_columns(stats: build_run_stats(stats), updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      run.broadcast_progress
    end

    def broadcast_all_step_runs(run, step_runs, stats)
      STAGE_ORDER.each { |stage| broadcast_step_run_progress(step_runs[stage], stats, stage) }
      broadcast_run_progress(run, stats) # single refresh covers all step run card updates
    end

    def build_run_stats(stats)
      {
        "documents_loaded" => stats[:documents_loaded],
        "documents_skipped" => stats[:documents_skipped],
        "chunks_created" => stats[:chunks_created],
        "embeddings_generated" => stats[:embeddings_generated],
        "documents_stored" => stats[:documents_stored],
      }
    end

    def step_output_count(stage, stats)
      case stage
      when :source then stats[:documents_loaded]
      when :chunking then stats[:chunks_created]
      when :embedding then stats[:embeddings_generated]
      when :storage then stats[:documents_stored]
      else
        # :nocov:
        0
        # :nocov:
      end
    end

    def step_input_count(stage, stats)
      case stage
      when :chunking, :storage then stats[:documents_loaded]
      when :embedding then stats[:chunks_created]
      else
        # :nocov:
        0
        # :nocov:
      end
    end

    def complete_run(run)
      run.rag_step_runs.pending.update_all(status: :skipped) # rubocop:disable Rails/SkipsModelValidations
      run.update!(
        status: :completed,
        completed_at: Time.current,
        stats: aggregate_stats(run),
      )
      run.broadcast_progress
    end

    def cancel_run(run)
      run.update!(status: :cancelled, completed_at: Time.current, stats: aggregate_stats(run))
      run.rag_step_runs.where(status: ["pending", "running"]).update_all(status: :skipped) # rubocop:disable Rails/SkipsModelValidations
      run.broadcast_progress
    end

    def fail_run(run, error)
      run.update!(
        status: :failed,
        completed_at: Time.current,
        error_message: error.message.truncate(1000),
        stats: aggregate_stats(run),
      )

      run.rag_step_runs.pending.update_all(status: :skipped) # rubocop:disable Rails/SkipsModelValidations
      run.broadcast_progress
    end

    def aggregate_stats(run)
      step_runs = run.rag_step_runs.reload
      stats = {}

      step_runs.each do |sr|
        sr.stats.each do |key, value|
          # :nocov:
          next unless value.is_a?(Numeric)
          # :nocov:

          stats[key] = (stats[key] || 0) + value
        end
      end

      stats["duration_seconds"] = run.duration&.round(2)
      stats
    end
  end
end
