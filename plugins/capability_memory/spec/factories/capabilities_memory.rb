# frozen_string_literal: true

FactoryBot.define do
  factory :capabilities_memory_standalone, class: "Capabilities::Memory" do
    model_id { "text-embedding-3-small" }
    embedding_dimensions { 1536 }
    auto_bootstrap { true }
  end
end
