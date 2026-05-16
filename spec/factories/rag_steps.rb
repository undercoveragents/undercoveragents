# frozen_string_literal: true

# == Schema Information
#
# Table name: rag_steps
# Database name: primary
#
#  id            :bigint           not null, primary key
#  configuration :jsonb            not null
#  module_type   :string           not null
#  stage         :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  rag_flow_id   :bigint           not null
#
# Indexes
#
#  idx_rag_steps_flow_stage        (rag_flow_id,stage) UNIQUE
#  index_rag_steps_on_rag_flow_id  (rag_flow_id)
#
# Foreign Keys
#
#  fk_rails_...  (rag_flow_id => rag_flows.id)
#
FactoryBot.define do
  factory :rag_step do
    rag_flow
    stage { "source" }
    module_type { "sql_database_source" }
    configuration { {} }

    trait :source do
      stage { "source" }
      module_type { "sql_database_source" }
      configuration do
        connector = association(:connector, :sql_database, :enabled)
        {
          "connector_id" => connector.id,
          "query" => "SELECT id, content FROM documents",
          "content_column" => "content",
          "metadata_columns" => [],
          "batch_size" => 1000,
        }
      end
    end

    trait :chunking do
      stage { "chunking" }
      module_type { "fixed_size_chunker" }
      configuration do
        {
          "chunk_size" => 1000,
          "chunk_overlap" => 200,
        }
      end
    end

    trait :embedding do
      stage { "embedding" }
      module_type { "llm_embedder" }
      configuration do
        llm_connector = association(:connector, :llm_provider, :enabled)
        {
          "llm_connector_id" => llm_connector.id,
          "model_id" => "text-embedding-3-small",
          "batch_size" => 100,
          "max_tokens_per_batch" => 6000,
        }
      end
    end

    trait :storage do
      stage { "storage" }
      module_type { "sql_database_storage" }
      configuration do
        connector = association(:connector, :sql_database, :enabled)
        {
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
        }
      end
    end
  end
end
