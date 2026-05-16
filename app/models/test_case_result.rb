# frozen_string_literal: true

# == Schema Information
#
# Table name: test_case_results
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  actual_answer             :text
#  actual_child_builtin_keys :jsonb            not null
#  actual_status             :string
#  actual_tool_names         :jsonb            not null
#  actual_variables          :jsonb            not null
#  analysis                  :text
#  behavior_analysis         :text
#  behavior_passed           :boolean
#  completed_at              :datetime
#  debug_snapshot            :jsonb            not null
#  duration_ms               :integer
#  passed                    :boolean
#  score                     :float
#  semantic_passed           :boolean
#  started_at                :datetime
#  status                    :string           default("pending"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  chat_id                   :bigint
#  mission_run_id            :bigint
#  test_case_id              :bigint           not null
#  test_suite_run_id         :bigint           not null
#
# Indexes
#
#  idx_test_case_results_on_run_and_case         (test_suite_run_id,test_case_id) UNIQUE
#  index_test_case_results_on_chat_id            (chat_id)
#  index_test_case_results_on_mission_run_id     (mission_run_id)
#  index_test_case_results_on_status             (status)
#  index_test_case_results_on_test_case_id       (test_case_id)
#  index_test_case_results_on_test_suite_run_id  (test_suite_run_id)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (mission_run_id => mission_runs.id)
#  fk_rails_...  (test_case_id => test_cases.id)
#  fk_rails_...  (test_suite_run_id => test_suite_runs.id)
#
class TestCaseResult < ApplicationRecord
  enum :status, {
    pending: "pending",
    running: "running",
    evaluating: "evaluating",
    passed: "passed",
    failed: "failed",
    error: "error",
  }, default: :pending
  belongs_to :test_suite_run, inverse_of: :test_case_results
  belongs_to :test_case, inverse_of: :test_case_results
  belongs_to :chat, optional: true
  belongs_to :mission_run, optional: true

  scope :ordered, -> { order(:created_at) }
  validates :score, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 },
                    allow_nil: true
  validate :debug_json_columns_must_have_expected_shape

  before_validation :normalize_debug_json_columns

  def completed?
    passed? || failed? || error?
  end

  def duration_seconds
    return nil unless duration_ms

    (duration_ms / 1000.0).round(2)
  end

  def related_chats
    return Chat.none unless chat

    Chat.where(id: chat.id).or(Chat.where(parent_chat_id: chat.id))
  end

  def related_messages
    return Message.none unless chat

    Message.where(chat_id: related_chats.select(:id))
  end

  def input_tokens
    related_messages.sum(Message.total_input_activity_sum)
  end

  def output_tokens
    related_messages.sum(:output_tokens)
  end

  def total_tokens
    input_tokens + output_tokens
  end

  def calculate_cost
    return 0 unless chat

    related_chats.includes(:model, messages: [:model, { chat: :model }]).sum(&:calculate_cost)
  end

  def agent_input_tokens
    context_input_tokens(:test)
  end

  def agent_output_tokens
    context_output_tokens(:test)
  end

  def evaluator_input_tokens
    context_input_tokens(:system)
  end

  def evaluator_output_tokens
    context_output_tokens(:system)
  end

  def agent_cost
    context_cost(:test)
  end

  def evaluator_cost
    context_cost(:system)
  end

  def node_executions
    return [] unless mission_run

    mission_run.node_executions
  end

  def execution_node_count
    node_executions.size
  end

  private

  def normalize_debug_json_columns
    self.actual_variables = {} unless actual_variables.is_a?(Hash)
    self.actual_tool_names = normalized_string_array(actual_tool_names)
    self.actual_child_builtin_keys = normalized_string_array(actual_child_builtin_keys)
    self.debug_snapshot = {} unless debug_snapshot.is_a?(Hash)
  end

  def normalized_string_array(value)
    Array(value).filter_map { |item| item.to_s.strip.presence }
  end

  def debug_json_columns_must_have_expected_shape
    errors.add(:actual_variables, "must be a JSON object") unless actual_variables.is_a?(Hash)
    errors.add(:actual_tool_names, "must be an array") unless actual_tool_names.is_a?(Array)
    errors.add(:actual_child_builtin_keys, "must be an array") unless actual_child_builtin_keys.is_a?(Array)
    errors.add(:debug_snapshot, "must be a JSON object") unless debug_snapshot.is_a?(Hash)
  end

  def context_input_tokens(context)
    Message.joins(:chat)
           .where(chat_id: related_chats.where(execution_context: context).select(:id))
           .sum(Message.total_input_activity_sum)
  end

  def context_output_tokens(context)
    Message.joins(:chat).where(chat_id: related_chats.where(execution_context: context).select(:id)).sum(:output_tokens)
  end

  def context_cost(context)
    chats = related_chats.where(execution_context: context)
    chats.includes(:model, messages: [:model, { chat: :model }]).sum(&:calculate_cost)
  end
end
