# frozen_string_literal: true

# Builds a configurator instance (ActiveModel, not AR).
FactoryBot.define do
  factory :rag_steps_sentence_chunker, class: "RagSteps::SentenceChunker" do
    skip_create

    chunk_size { 1000 }
    chunk_overlap { 200 }

    initialize_with { new(attributes) }
  end
end
