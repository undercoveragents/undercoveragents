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
FactoryBot.define do
  factory :test_case_result do
    test_suite_run
    test_case
    status { "pending" }

    trait :pending do
      status { "pending" }
    end

    trait :running do
      status { "running" }
      started_at { Time.current }
    end

    trait :evaluating do
      status { "evaluating" }
      started_at { Time.current }
    end

    trait :passed do
      status { "passed" }
      passed { true }
      actual_answer { Faker::Lorem.paragraph }
      analysis { "The answer matches the expected output." }
      score { 0.95 }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      duration_ms { 2500 }
    end

    trait :failed do
      status { "failed" }
      passed { false }
      actual_answer { Faker::Lorem.paragraph }
      analysis { "The answer does not match the expected output." }
      score { 0.3 }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      duration_ms { 3000 }
    end

    trait :error do
      status { "error" }
      passed { false }
      analysis { "An error occurred during execution." }
      started_at { 1.minute.ago }
      completed_at { Time.current }
    end

    trait :with_chat do
      chat { association :chat, :test_context }
    end
  end
end
