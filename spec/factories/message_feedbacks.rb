# frozen_string_literal: true

FactoryBot.define do
  factory :message_feedback do
    message { association(:message, :assistant) }
    chat { message.chat }
    user { message.chat.user || association(:user) }
    value { "positive" }
    category { nil }
    comment { nil }

    trait :negative do
      value { "negative" }
      category { "incorrect" }
      comment { "The answer was incorrect." }
    end
  end
end
