# frozen_string_literal: true

# Builds a Tools::RagQuery JSONB configurator (ActiveModel, not AR).
# `create` also generates a backing Tool AR record with _tool_record set.
FactoryBot.define do
  factory :tools_rag_query, class: "Tools::RagQuery" do
    skip_create

    transient do
      tool_name { Faker::Lorem.unique.words(number: 3).join(" ").titleize }
    end

    connector factory: [:connector, :sql_database]
    chunks_table { "chunks" }
    documents_table { "documents" }
    chunk_content_field { "content" }
    embedding_field { "embedding" }
    document_reference_field { "document_id" }
    document_fields { [{ "name" => "title" }, { "name" => "url" }] }
    distance_method { "cosine" }
    max_distance { 0.8 }
    results_limit { 10 }
    custom_instructions { nil }
    discovered_schema { {} }

    initialize_with { new(attributes.except(:tool_name)) }

    after(:create) do |rq, evaluator|
      tool = Tool.new(
        tool_type: "rag_query",
        name: evaluator.tool_name,
        operation: OperationFactoryHelper.default_operation,
      )
      tool.configurator = rq
      tool.save!
      rq._tool_record = tool
    end

    trait :with_llm do
      llm_connector factory: [:connector, :llm_provider, :enabled]
      embedding_model_id { "text-embedding-3-small" }
    end

    trait :with_schema do
      discovered_schema do
        {
          "objects" => [
            {
              "type" => "table",
              "name" => "chunks",
              "columns" => [
                { "name" => "id", "type" => "integer", "nullable" => false },
                { "name" => "content", "type" => "text", "nullable" => false },
                { "name" => "embedding", "type" => "vector", "nullable" => false },
                { "name" => "document_id", "type" => "integer", "nullable" => false },
              ],
            },
            {
              "type" => "table",
              "name" => "documents",
              "columns" => [
                { "name" => "id", "type" => "integer", "nullable" => false },
                { "name" => "title", "type" => "character varying", "nullable" => false },
                { "name" => "url", "type" => "character varying", "nullable" => true },
              ],
            },
          ],
        }
      end
      schema_discovered_at { Time.current }
    end
  end
end
