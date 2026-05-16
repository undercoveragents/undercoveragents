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
FactoryBot.define do
  factory :rag_step_run do
    rag_run
    step_type { "source" }
    position { 1 }
    status { "pending" }

    trait :pending do
      status { "pending" }
    end

    trait :running do
      status { "running" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      started_at { 2.minutes.ago }
      completed_at { Time.current }
      input_count { 10 }
      output_count { 10 }
    end

    trait :failed do
      status { "failed" }
      started_at { 2.minutes.ago }
      completed_at { Time.current }
      error_message { "Execution error" }
    end

    trait :skipped do
      status { "skipped" }
    end

    trait :source do
      step_type { "source" }
      position { 1 }
    end

    trait :chunking do
      step_type { "chunking" }
      position { 2 }
    end

    trait :embedding do
      step_type { "embedding" }
      position { 3 }
    end

    trait :storage do
      step_type { "storage" }
      position { 4 }
    end
  end
end
