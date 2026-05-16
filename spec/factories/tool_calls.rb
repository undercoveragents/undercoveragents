# frozen_string_literal: true

# == Schema Information
#
# Table name: tool_calls
# Database name: primary
#
#  id                :bigint           not null, primary key
#  arguments         :jsonb
#  display_name      :string
#  duration_ms       :integer
#  icon              :string
#  name              :string           not null
#  thought_signature :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  message_id        :bigint           not null
#  tool_call_id      :string           not null
#
# Indexes
#
#  index_tool_calls_on_message_id    (message_id)
#  index_tool_calls_on_name          (name)
#  index_tool_calls_on_tool_call_id  (tool_call_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (message_id => messages.id)
#
FactoryBot.define do
  factory :tool_call do
    message
    name { "sql_query_test" }
    sequence(:tool_call_id) { |n| "call_#{n}" }
    arguments { { "question" => "How many users?" } }

    trait :with_duration do
      duration_ms { rand(50..3000) }
    end
  end
end
