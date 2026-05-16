# frozen_string_literal: true

# == Schema Information
#
# Table name: test_suite_runs
# Database name: primary
#
#  id             :bigint           not null, primary key
#  completed_at   :datetime
#  debug_snapshot :jsonb            not null
#  duration_ms    :integer
#  error_count    :integer          default(0), not null
#  failed_count   :integer          default(0), not null
#  passed_count   :integer          default(0), not null
#  started_at     :datetime
#  status         :string           default("pending"), not null
#  total_count    :integer          default(0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  test_suite_id  :bigint           not null
#  user_id        :bigint
#
# Indexes
#
#  index_test_suite_runs_on_status                        (status)
#  index_test_suite_runs_on_test_suite_id                 (test_suite_id)
#  index_test_suite_runs_on_test_suite_id_and_created_at  (test_suite_id,created_at)
#  index_test_suite_runs_on_user_id                       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (test_suite_id => test_suites.id)
#  fk_rails_...  (user_id => users.id)
#
class TestSuiteRun < ApplicationRecord
  CANCEL_NOT_PERFORMED = false
  CANCEL_PERFORMED = true
  enum :status, {
    pending: "pending",
    running: "running",
    evaluating: "evaluating",
    completed: "completed",
    failed: "failed",
    cancelled: "cancelled",
  }, default: :pending
  belongs_to :test_suite, inverse_of: :test_suite_runs
  belongs_to :user, optional: true

  has_many :test_case_results, -> { order(:created_at) }, dependent: :destroy, inverse_of: :test_suite_run

  scope :recent, -> { order(created_at: :desc) }
  validates :passed_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :failed_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :error_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :total_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :debug_snapshot_must_be_hash

  before_validation :normalize_debug_snapshot

  def progress_percentage
    return 0 if total_count.zero?

    completed = test_case_results.where(status: [:passed, :failed, :error]).count
    ((completed.to_f / total_count) * 100).round
  end

  def pass_rate
    return 0.0 if total_count.zero?

    ((passed_count.to_f / total_count) * 100).round(1)
  end

  def in_progress?
    running? || evaluating?
  end

  def cancel!
    return CANCEL_NOT_PERFORMED unless in_progress?

    update!(status: :cancelled, completed_at: Time.current)
    test_case_results.where(status: [:pending, :running, :evaluating]).update_all(status: :error) # rubocop:disable Rails/SkipsModelValidations
    CANCEL_PERFORMED
  end

  def compute_counts!
    results = test_case_results.reload
    update!(
      passed_count: results.where(status: :passed).count,
      failed_count: results.where(status: :failed).count,
      error_count: results.where(status: :error).count,
    )
  end

  # ── Token aggregations ─────────────────────────────────────────────
  # Each of these is a single SQL query that joins test_case_results →
  # related chats (direct + child) → messages, avoiding N+1 per result.
  # "Related chats" mirrors TestCaseResult#related_chats:
  #   chats whose id OR parent_chat_id matches the result's chat_id.

  def total_input_tokens
    run_messages_scope.sum(Message.total_input_activity_sum)
  end

  def total_output_tokens
    run_messages_scope.sum(:output_tokens)
  end

  def total_tokens
    total_input_tokens + total_output_tokens
  end

  def agent_input_tokens
    run_messages_scope(execution_context: "test").sum(Message.total_input_activity_sum)
  end

  def agent_output_tokens
    run_messages_scope(execution_context: "test").sum(:output_tokens)
  end

  def evaluator_input_tokens
    run_messages_scope(execution_context: "system").sum(Message.total_input_activity_sum)
  end

  def evaluator_output_tokens
    run_messages_scope(execution_context: "system").sum(:output_tokens)
  end

  # Cost methods require per-message model pricing, so they stay in Ruby.
  def calculate_cost
    test_case_results.includes(chat: [:model, { messages: [:model, { chat: :model }] }]).sum(&:calculate_cost)
  end

  def agent_cost
    test_case_results.includes(chat: [:model, { messages: [:model, { chat: :model }] }]).sum(&:agent_cost)
  end

  def evaluator_cost
    test_case_results.includes(chat: [:model, { messages: [:model, { chat: :model }] }]).sum(&:evaluator_cost)
  end

  private

  def normalize_debug_snapshot
    self.debug_snapshot = {} unless debug_snapshot.is_a?(Hash)
  end

  def debug_snapshot_must_be_hash
    errors.add(:debug_snapshot, "must be a JSON object") unless debug_snapshot.is_a?(Hash)
  end

  # Returns a Message scope that covers all chats associated with this run's
  # results: each result's own chat and any child chats (parent_chat_id).
  # Optionally filtered to a specific execution_context.
  def run_messages_scope(execution_context: nil)
    chat_subquery = test_case_results.where.not(chat_id: nil).select(:chat_id)

    scope = Message
            .joins(:chat)
            .where(
              "chats.id IN (:sq) OR chats.parent_chat_id IN (:sq)",
              sq: chat_subquery,
            )

    scope = scope.where(chats: { execution_context: }) if execution_context
    scope
  end
end
