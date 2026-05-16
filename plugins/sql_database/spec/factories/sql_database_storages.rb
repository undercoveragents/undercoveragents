# frozen_string_literal: true

# Builds a configurator instance (ActiveModel, not AR).
FactoryBot.define do
  factory :rag_steps_sql_database_storage, class: "RagSteps::SqlDatabaseStorage" do
    skip_create

    connector_id { nil }
    documents_table { "documents" }
    chunks_table { "chunks" }
    content_field { "content" }
    embedding_field { "embedding" }
    document_reference_field { "document_id" }
    metadata_field_mappings { {} }
    metadata_column_types { {} }
    pre_load_action { "none" }
    upsert_enabled { false }
    auto_create_tables { false }
    embedding_dimensions { 1536 }

    initialize_with { new(attributes) }

    trait :with_connector do
      transient do
        connector { association(:connector, :sql_database, :enabled) }
      end
      connector_id { connector.id }
    end
  end
end
