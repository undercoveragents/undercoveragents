# frozen_string_literal: true

module Rag
  # Structured context passed between steps during pipeline execution.
  # Provides execution metadata and a well-defined interface for inter-step
  # communication. This object is immutable and shared across all steps
  # within a single pipeline run.
  #
  # @example
  #   ctx = Rag::StepContext.new(run_id: 42, flow_id: 7)
  #   ctx.batch_number  # => 1
  #   ctx.next_batch    # => StepContext with batch_number: 2
  #
  StepContext = Data.define(:run_id, :flow_id, :batch_number, :total_batches, :metadata) do
    def initialize(run_id:, flow_id:, batch_number: 1, total_batches: nil, metadata: {})
      super
    end

    # Returns a new context for the next batch
    def next_batch
      with(batch_number: batch_number + 1)
    end

    # Returns a hash representation for backward compatibility
    def to_context_hash
      { run_id:, flow_id:, batch_number:, total_batches:, metadata: }
    end
  end
end
