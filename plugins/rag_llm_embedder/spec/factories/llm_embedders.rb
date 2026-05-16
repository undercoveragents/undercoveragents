# frozen_string_literal: true

# Builds a configurator instance (ActiveModel, not AR).
FactoryBot.define do
  factory :rag_steps_llm_embedder, class: "RagSteps::LlmEmbedder" do
    skip_create

    llm_connector_id { nil }
    model_id { "text-embedding-3-small" }
    batch_size { 100 }
    max_tokens_per_batch { 6000 }
    dimensions { nil }

    initialize_with { new(attributes) }

    trait :with_connector do
      transient do
        llm_connector { association(:connector, :llm_provider, :enabled) }
      end
      llm_connector_id { llm_connector.id }
    end
  end
end
