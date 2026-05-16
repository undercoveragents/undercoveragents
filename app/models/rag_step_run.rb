# frozen_string_literal: true

# == Schema Information
#
# Table name: rag_step_runs
# Database name: primary
#
#  id            :bigint           not null, primary key
#  completed_at  :datetime
#  error_message :text
#  input_count   :integer          default(0), not null
#  output_count  :integer          default(0), not null
#  position      :integer          not null
#  started_at    :datetime
#  stats         :jsonb            not null
#  status        :string           default("pending"), not null
#  step_type     :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  rag_run_id    :bigint           not null
#
# Indexes
#
#  idx_step_runs_on_run_and_type      (rag_run_id,step_type) UNIQUE
#  index_rag_step_runs_on_rag_run_id  (rag_run_id)
#
# Foreign Keys
#
#  fk_rails_...  (rag_run_id => rag_runs.id)
#
class RagStepRun < ApplicationRecord
  include Turbo::Broadcastable

  STEP_TYPES = RagStep::STAGES
  enum :status, {
    pending: "pending",
    running: "running",
    completed: "completed",
    failed: "failed",
    skipped: "skipped",
  }, default: :pending, validate: true
  belongs_to :rag_run, inverse_of: :rag_step_runs

  delegate :broadcast_progress, to: :rag_run
  scope :ordered, -> { order(:position) }
  validates :status, presence: true
  validates :step_type, presence: true, inclusion: { in: STEP_TYPES }
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }

  def duration
    return nil unless started_at

    (completed_at || Time.current) - started_at
  end

  def finished?
    completed? || failed? || skipped?
  end

  def step_label
    RagFlow::STAGES.find { |s| s[:key].to_s == step_type }&.dig(:label) || step_type.titleize
  end

  def step_icon
    RagFlow::STAGES.find { |s| s[:key].to_s == step_type }&.dig(:icon) || "fa-solid fa-circle"
  end

  def step_stage_key
    step_type.to_s
  end

  # Returns the module label (e.g. "SQL Database", "LLM Embedder") from the rag flow step
  def module_label
    step = rag_run.rag_flow.step_for(step_type)
    step&.configurator&.label
  end

  def primary_stat_value
    output_count
  end

  def primary_stat_label
    case step_type
    when "source" then "documents"
    when "chunking" then "chunks"
    when "embedding" then "embeddings"
    when "storage" then "stored"
    else "records"
    end
  end

  def skipped_count
    return unless step_type == "source"

    stats["documents_skipped"] || 0
  end
end
