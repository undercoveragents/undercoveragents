# frozen_string_literal: true

# Builds a configurator instance (ActiveModel, not AR).
FactoryBot.define do
  factory :rag_steps_paragraph_chunker, class: "RagSteps::ParagraphChunker" do
    skip_create

    chunk_size { 1000 }
    chunk_overlap { 200 }
    min_paragraph_size { 100 }

    initialize_with { new(attributes) }
  end
end
