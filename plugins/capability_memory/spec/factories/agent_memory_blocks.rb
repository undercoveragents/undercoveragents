# frozen_string_literal: true

FactoryBot.define do
  factory :agent_memory_block do
    agent
    memory_block
    user
    value { "" }
  end
end
