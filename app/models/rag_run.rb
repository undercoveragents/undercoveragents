# frozen_string_literal: true

# == Schema Information
#
# Table name: rag_runs
# Database name: primary
#
#  id            :bigint           not null, primary key
#  completed_at  :datetime
#  error_message :text
#  started_at    :datetime
#  stats         :jsonb            not null
#  status        :string           default("pending"), not null
#  triggered_by  :string           default("manual"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  rag_flow_id   :bigint           not null
#
# Indexes
#
#  index_rag_runs_on_rag_flow_id             (rag_flow_id)
#  index_rag_runs_on_rag_flow_id_and_status  (rag_flow_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (rag_flow_id => rag_flows.id)
#
class RagRun < ApplicationRecord
  include Turbo::Broadcastable

  # A run is considered stale when it has been running/pending without a heartbeat
  # update for longer than this duration — indicates the worker process likely crashed.
  STALE_TIMEOUT = 5.minutes
  TRIGGERED_BY_OPTIONS = ["manual", "scheduled", "webhook"].freeze
  CANCEL_NOT_PERFORMED = false
  CANCEL_PERFORMED = true
  enum :status, {
    pending: "pending",
    running: "running",
    completed: "completed",
    failed: "failed",
    cancelled: "cancelled",
  }, default: :pending, validate: true
  belongs_to :rag_flow, inverse_of: :rag_runs

  has_many :rag_step_runs, dependent: :destroy, inverse_of: :rag_run

  scope :recent, -> { order(created_at: :desc).limit(10) }
  scope :ordered, -> { order(created_at: :desc) }
  validates :status, presence: true
  validates :triggered_by, presence: true, inclusion: { in: TRIGGERED_BY_OPTIONS }

  def duration
    return nil unless started_at

    (completed_at || Time.current) - started_at
  end

  def cancel!
    return CANCEL_NOT_PERFORMED unless running? || pending?

    update!(status: :cancelled, completed_at: Time.current)
    rag_step_runs.pending.update_all(status: :skipped) # rubocop:disable Rails/SkipsModelValidations
    CANCEL_PERFORMED
  end

  def finished?
    completed? || failed? || cancelled?
  end

  # True when a running/pending run has not received a heartbeat within STALE_TIMEOUT.
  # PipelineExecutor keeps updated_at fresh on every batch via broadcast_run_progress.
  # If the worker process crashed (e.g. SIGSEGV), updated_at will stop advancing and
  # the run will be detected as stale after STALE_TIMEOUT elapses.
  def stale?
    return false if finished?

    updated_at < STALE_TIMEOUT.ago
  end

  # If the run is stale, mark it as failed and clean up stuck step runs.
  # Idempotent — safe to call on every page load.
  def recover_if_stale!
    return unless stale?

    update!(
      status: :failed,
      completed_at: Time.current,
      error_message: "Worker process terminated unexpectedly (possible crash or out-of-memory).",
    )
    rag_step_runs.where(status: ["pending", "running"]).update_all(status: :skipped) # rubocop:disable Rails/SkipsModelValidations
    broadcast_progress
  end

  def documents_loaded
    stats["documents_loaded"] || 0
  end

  def documents_skipped
    stats["documents_skipped"] || 0
  end

  def documents_processed
    documents_loaded - documents_skipped
  end

  def chunks_created
    stats["chunks_created"] || 0
  end

  def embeddings_generated
    stats["embeddings_generated"] || 0
  end

  def documents_stored
    stats["documents_stored"] || 0
  end

  def broadcast_progress
    broadcast_replace_to(
      "rag_run_#{id}",
      target: "rag-run-#{id}",
      partial: "admin/rag/runs/run_detail",
      locals: { run: self },
    )
  rescue PG::InvalidParameterValue => e
    Rails.logger.warn("[RagRun] Broadcast skipped for run #{id} — PG payload too large: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("[RagRun] Broadcast error for run #{id}: #{e.class} — #{e.message} (#{e.backtrace&.first})")
  end
end
