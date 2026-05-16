# frozen_string_literal: true

# Builds a configurator instance (ActiveModel, not AR).
# Use `build` only — `create` is not supported for non-AR models.
FactoryBot.define do
  factory :rag_steps_sql_database_source, class: "RagSteps::SqlDatabaseSource" do
    skip_create

    connector_id { nil }
    query { "SELECT id, content FROM documents" }
    content_column { "content" }
    metadata_columns { [] }
    batch_size { 1000 }

    initialize_with { new(attributes) }

    trait :with_connector do
      transient do
        connector { association(:connector, :sql_database, :enabled) }
      end
      connector_id { connector.id }
    end
  end
end
