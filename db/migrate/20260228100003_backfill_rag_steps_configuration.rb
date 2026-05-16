# frozen_string_literal: true

class BackfillRagStepsConfiguration < ActiveRecord::Migration[8.1]
  def up # rubocop:disable Metrics/MethodLength,Metrics/AbcSize,Metrics/CyclomaticComplexity
    # Map steppable_type to module_type key
    type_map = {
      "RagSteps::SqlDatabaseSource" => "sql_database_source",
      "RagSteps::FixedSizeChunker" => "fixed_size_chunker",
      "RagSteps::ParagraphChunker" => "paragraph_chunker",
      "RagSteps::SentenceChunker" => "sentence_chunker",
      "RagSteps::MarkdownChunker" => "markdown_chunker",
      "RagSteps::LlmEmbedder" => "llm_embedder",
      "RagSteps::SqlDatabaseStorage" => "sql_database_storage",
      # Placeholders (will be deleted, but migrate any existing rows)
      "RagSteps::FileSource" => "file_source",
      "RagSteps::ElasticsearchSource" => "elasticsearch_source",
      "RagSteps::CustomCodeSource" => "custom_code_source",
      "RagSteps::CustomCodeChunker" => "custom_code_chunker",
      "RagSteps::CustomCodeEmbedder" => "custom_code_embedder",
      "RagSteps::ElasticsearchStorage" => "elasticsearch_storage",
      "RagSteps::CustomCodeStorage" => "custom_code_storage",
    }

    # Tables and their configuration columns (excluding id, created_at, updated_at)
    config_columns = {
      "sql_database_source" => {
        table: "rag_steps_sql_database_sources",
        columns: %w[connector_id query content_column metadata_columns batch_size incremental_column last_incremental_value],
      },
      "fixed_size_chunker" => {
        table: "rag_steps_fixed_size_chunkers",
        columns: %w[chunk_size chunk_overlap separator],
      },
      "paragraph_chunker" => {
        table: "rag_steps_paragraph_chunkers",
        columns: %w[chunk_size chunk_overlap min_paragraph_size],
      },
      "sentence_chunker" => {
        table: "rag_steps_sentence_chunkers",
        columns: %w[chunk_size chunk_overlap],
      },
      "markdown_chunker" => {
        table: "rag_steps_markdown_chunkers",
        columns: %w[chunk_size chunk_overlap],
      },
      "llm_embedder" => {
        table: "rag_steps_llm_embedders",
        columns: %w[llm_connector_id model_id batch_size max_tokens_per_batch dimensions],
      },
      "sql_database_storage" => {
        table: "rag_steps_sql_database_storages",
        columns: %w[connector_id documents_table chunks_table content_field embedding_field
                     document_reference_field pre_load_action upsert_enabled auto_create_tables
                     embedding_dimensions metadata_column_types metadata_field_mappings],
      },
    }

    # Backfill each rag_step
    execute <<~SQL.squish
      SELECT id, steppable_type, steppable_id FROM rag_steps
    SQL

    select_all("SELECT id, steppable_type, steppable_id FROM rag_steps").each do |step|
      module_type = type_map[step["steppable_type"]]
      next unless module_type

      configuration = {}

      # Load configuration from the steppable table if it has config columns
      if config_columns[module_type]
        info = config_columns[module_type]
        cols = info[:columns].join(", ")
        row = select_one("SELECT #{cols} FROM #{info[:table]} WHERE id = #{step["steppable_id"]}")
        if row
          info[:columns].each do |col|
            value = row[col]
            configuration[col] = value unless value.nil?
          end
        end
      end

      # Update the rag_step with module_type and configuration
      escaped_config = connection.quote(configuration.to_json)
      escaped_module_type = connection.quote(module_type)
      execute("UPDATE rag_steps SET module_type = #{escaped_module_type}, " \
              "configuration = #{escaped_config} WHERE id = #{step["id"]}")
    end

    # Now make module_type NOT NULL
    change_column_null :rag_steps, :module_type, false
  end

  def down
    change_column_null :rag_steps, :module_type, true
    # Data reverse migration is not feasible — the steppable tables would need to be re-populated
  end
end
