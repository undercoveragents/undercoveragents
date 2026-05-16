# frozen_string_literal: true

FactoryBot.define do
  factory :archival_memory do
    agent
    user
    content   { Faker::Lorem.paragraph }
    embedding { Array.new(1536) { rand(-1.0..1.0) } }
    tags      { [] }

    trait :tagged do
      tags { [Faker::Lorem.word, Faker::Lorem.word] }
    end
  end
end
