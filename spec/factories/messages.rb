# frozen_string_literal: true

# == Schema Information
#
# Table name: messages
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  cache_creation_tokens :integer
#  cached_tokens         :integer
#  content               :text
#  content_raw           :json
#  duration_ms           :integer
#  input_tokens          :integer
#  output_tokens         :integer
#  role                  :string           not null
#  thinking_signature    :text
#  thinking_text         :text
#  thinking_tokens       :integer
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  chat_id               :bigint           not null
#  model_id              :bigint
#  tool_call_id          :bigint
#
# Indexes
#
#  index_messages_on_chat_id       (chat_id)
#  index_messages_on_model_id      (model_id)
#  index_messages_on_role          (role)
#  index_messages_on_tool_call_id  (tool_call_id)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (model_id => models.id)
#  fk_rails_...  (tool_call_id => tool_calls.id)
#
FactoryBot.define do
  factory :message do
    chat
    role { "assistant" }
    content { Faker::Lorem.paragraph }
    input_tokens { 100 }
    output_tokens { 50 }
    cached_tokens { 0 }
    cache_creation_tokens { 0 }

    trait :user do
      role { "user" }
      output_tokens { 0 }
      input_tokens { 0 }
      cached_tokens { 0 }
    end

    trait :assistant do
      role { "assistant" }
    end

    trait :tool do
      role { "tool" }
    end

    trait :system do
      role { "system" }
    end

    trait :with_model do
      model
    end

    trait :with_null_bytes do
      content { "Hello\u0000World" }
      thinking_text { "Thinking\u0000stuff" }
      content_raw { { "text" => "Raw\u0000content" } }
    end

    trait :with_duration do
      duration_ms { rand(100..5000) }
    end
  end
end
