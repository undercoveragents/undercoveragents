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
FactoryBot.define do
  factory :rag_run do
    rag_flow
    status { "pending" }
    triggered_by { "manual" }

    trait :pending do
      status { "pending" }
    end

    trait :running do
      status { "running" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      stats { { "documents_loaded" => 10, "chunks_created" => 50, "embeddings_generated" => 50 } }
    end

    trait :failed do
      status { "failed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      error_message { "Connection refused" }
    end

    trait :cancelled do
      status { "cancelled" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
    end
  end
end
