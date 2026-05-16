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
FactoryBot.define do
  factory :test_suite_run do
    test_suite
    status { "pending" }
    passed_count { 0 }
    failed_count { 0 }
    error_count { 0 }
    total_count { 0 }

    trait :pending do
      status { "pending" }
    end

    trait :running do
      status { "running" }
      started_at { Time.current }
      total_count { 3 }
    end

    trait :evaluating do
      status { "evaluating" }
      started_at { Time.current }
      total_count { 3 }
    end

    trait :completed do
      status { "completed" }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      total_count { 3 }
      passed_count { 2 }
      failed_count { 1 }
      duration_ms { 5000 }
    end

    trait :failed do
      status { "failed" }
      started_at { 1.minute.ago }
      completed_at { Time.current }
    end

    trait :cancelled do
      status { "cancelled" }
      started_at { 1.minute.ago }
      completed_at { Time.current }
    end
  end
end
