# frozen_string_literal: true

# == Schema Information
#
# Table name: rag_flows
# Database name: primary
#
#  id           :bigint           not null, primary key
#  enabled      :boolean          default(TRUE), not null
#  name         :string           not null
#  slug         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  operation_id :bigint           not null
#
# Indexes
#
#  index_rag_flows_on_operation_id           (operation_id)
#  index_rag_flows_on_operation_id_and_name  (operation_id,name) UNIQUE
#  index_rag_flows_on_slug                   (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
FactoryBot.define do
  factory :rag_flow do
    operation { OperationFactoryHelper.default_operation }
    name { Faker::Lorem.unique.words(number: 3).join(" ").titleize }
    enabled { true }

    trait :enabled do
      enabled { true }
    end

    trait :disabled do
      enabled { false }
    end

    trait :with_steps do
      after(:create) do |flow|
        connector = create(:connector, :sql_database, :enabled)
        llm_connector = create(:connector, :llm_provider, :enabled)

        create(:rag_step, rag_flow: flow, stage: "source",
                          module_type: "sql_database_source",
                          configuration: {
                            "connector_id" => connector.id,
                            "query" => "SELECT id, content FROM documents",
                            "content_column" => "content",
                            "metadata_columns" => [],
                            "batch_size" => 1000,
                          },)

        create(:rag_step, rag_flow: flow, stage: "chunking",
                          module_type: "fixed_size_chunker",
                          configuration: { "chunk_size" => 1000, "chunk_overlap" => 200 },)

        create(:rag_step, rag_flow: flow, stage: "embedding",
                          module_type: "llm_embedder",
                          configuration: {
                            "llm_connector_id" => llm_connector.id,
                            "model_id" => "text-embedding-3-small",
                            "batch_size" => 100,
                            "max_tokens_per_batch" => 6000,
                          },)

        create(:rag_step, rag_flow: flow, stage: "storage",
                          module_type: "sql_database_storage",
                          configuration: {
                            "connector_id" => connector.id,
                            "documents_table" => "documents",
                            "chunks_table" => "chunks",
                            "content_field" => "content",
                            "embedding_field" => "embedding",
                            "document_reference_field" => "document_id",
                            "pre_load_action" => "none",
                            "upsert_enabled" => false,
                            "auto_create_tables" => false,
                            "embedding_dimensions" => 1536,
                            "metadata_column_types" => {},
                            "metadata_field_mappings" => {},
                          },)
      end
    end
  end
end
