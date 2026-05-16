# frozen_string_literal: true

FactoryBot.define do
  factory :memory_block do
    sequence(:label) { |n| "block_#{("a".."z").to_a[n % 26] * ((n / 26) + 1)}" }
    description   { Faker::Lorem.sentence }
    default_value { Faker::Lorem.paragraph }
    char_limit    { 5000 }
    read_only { false }

    trait :read_only do
      read_only { true }
    end

    trait :persona do
      label       { "persona" }
      description { "Stores details about the agent's persona." }
    end

    trait :human do
      label       { "human" }
      description { "Stores key details about the person being conversed with." }
    end

    trait :full do
      default_value { Faker::Lorem.characters(number: 4900) }
    end

    trait :empty do
      default_value { "" }
    end
  end
end
