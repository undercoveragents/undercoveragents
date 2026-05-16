# frozen_string_literal: true

module Rag
  class ExecutionJob < ApplicationJob
    queue_as :default

    discard_on ActiveRecord::RecordNotFound

    def perform(rag_flow_id, tenant_id: nil, triggered_by: "manual", run_id: nil)
      pipeline = find_flow(rag_flow_id, tenant_id:)
      return unless pipeline

      existing_run = find_run(run_id, tenant_id:)
      Rag::PipelineExecutor.call(pipeline, triggered_by:, run: existing_run)
    rescue Rag::PipelineExecutor::ExecutionError => e
      Rails.logger.error("RAG #{rag_flow_id} failed: #{e.message}")
    rescue StandardError => e
      # Fallback for errors that escaped PipelineExecutor's own rescue (e.g. fail_run itself raised).
      Rails.logger.error("RAG #{rag_flow_id} unexpected error: #{e.class}: #{e.message}")
      mark_run_failed_if_active(existing_run&.id, e)
    end

    private

    def find_flow(rag_flow_id, tenant_id: nil)
      scope = RagFlow
      return scope.find_by(id: rag_flow_id) if tenant_id.blank?

      scope.joins(:operation).find_by(id: rag_flow_id, operations: { tenant_id: })
    end

    def find_run(run_id, tenant_id: nil)
      return if run_id.blank?

      scope = RagRun
      return scope.find_by(id: run_id) if tenant_id.blank?

      scope.joins(rag_flow: :operation).find_by(id: run_id, operations: { tenant_id: })
    end

    def mark_run_failed_if_active(run_id, error)
      return unless run_id

      RagRun.where(id: run_id, status: [:pending, :running]).update_all( # rubocop:disable Rails/SkipsModelValidations
        status: :failed,
        completed_at: Time.current,
        error_message: error.message.truncate(1000),
      )
    end
  end
end
