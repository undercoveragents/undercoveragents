# frozen_string_literal: true

class CreateRagSystem < ActiveRecord::Migration[8.1]
  def up
    # ── Drop legacy rag tables (from deleted migrations) ──
    drop_table :rag_step_runs, if_exists: true
    drop_table :rag_runs, if_exists: true
    drop_table :rag_steps_vector_stores, if_exists: true
    drop_table :rag_steps_embedders, if_exists: true
    drop_table :rag_steps_chunkers, if_exists: true
    drop_table :rag_steps_database_sources, if_exists: true
    drop_table :rag_flows, if_exists: true

    # ── Core: RAG ──
    create_table :rag_flows do |t|
      t.references :pipeline_version, null: false, foreign_key: true

      t.string :name, null: false
      t.string :slug, null: false
      t.boolean :enabled, null: false, default: false

      t.timestamps
    end

    add_index :rag_flows, [:pipeline_version_id, :name], unique: true
    add_index :rag_flows, [:pipeline_version_id, :slug], unique: true

    # ── Step wrapper (delegated_type :steppable) ──
    create_table :rag_steps do |t|
      t.references :rag_flow, null: false, foreign_key: true

      t.string :stage, null: false # source, chunking, embedding, storage
      t.string :steppable_type, null: false
      t.bigint :steppable_id, null: false

      t.timestamps
    end

    add_index :rag_steps, [:rag_flow_id, :stage],
              unique: true, name: "idx_rag_steps_flow_stage"
    add_index :rag_steps, [:steppable_type, :steppable_id],
              name: "idx_rag_steps_steppable"

    # ── Source modules ──

    create_table :rag_steps_sql_database_sources do |t|
      t.references :connector, null: false, foreign_key: { to_table: :connectors }

      t.text :query, null: false
      t.string :content_column, null: false
      t.jsonb :metadata_columns, null: false, default: []
      t.string :incremental_column
      t.string :last_incremental_value
      t.integer :batch_size, null: false, default: 1000

      t.timestamps
    end

    create_table :rag_steps_file_sources do |t|
      t.timestamps
    end

    create_table :rag_steps_elasticsearch_sources do |t|
      t.timestamps
    end

    # ── Chunking modules ──

    create_table :rag_steps_fixed_size_chunkers do |t|
      t.integer :chunk_size, null: false, default: 1000
      t.integer :chunk_overlap, null: false, default: 200
      t.string :separator

      t.timestamps
    end

    create_table :rag_steps_paragraph_chunkers do |t|
      t.integer :chunk_size, null: false, default: 1000
      t.integer :chunk_overlap, null: false, default: 200
      t.integer :min_paragraph_size, null: false, default: 100

      t.timestamps
    end

    create_table :rag_steps_markdown_chunkers do |t|
      t.integer :chunk_size, null: false, default: 1000
      t.integer :chunk_overlap, null: false, default: 200

      t.timestamps
    end

    create_table :rag_steps_sentence_chunkers do |t|
      t.integer :chunk_size, null: false, default: 1000
      t.integer :chunk_overlap, null: false, default: 200

      t.timestamps
    end

    # ── Embedding modules ──

    create_table :rag_steps_llm_embedders do |t|
      t.references :llm_connector, null: false, foreign_key: { to_table: :connectors }

      t.string :model_id, null: false
      t.integer :batch_size, null: false, default: 100
      t.integer :max_tokens_per_batch, null: false, default: 6000
      t.integer :dimensions

      t.timestamps
    end

    # ── Storage modules ──

    create_table :rag_steps_sql_database_storages do |t|
      t.references :connector, null: false, foreign_key: { to_table: :connectors }

      t.string :documents_table, null: false
      t.string :chunks_table, null: false
      t.string :content_field, null: false, default: "content"
      t.string :embedding_field, null: false, default: "embedding"
      t.string :document_reference_field, null: false, default: "document_id"
      t.jsonb :metadata_field_mappings, null: false, default: {}
      t.jsonb :metadata_column_types, null: false, default: {}
      t.string :pre_load_action, null: false, default: "none"
      t.boolean :upsert_enabled, null: false, default: false
      t.boolean :auto_create_tables, null: false, default: false
      t.integer :embedding_dimensions, null: false, default: 1536

      t.timestamps
    end

    create_table :rag_steps_elasticsearch_storages do |t|
      t.timestamps
    end

    # ── Runs ──

    create_table :rag_runs do |t|
      t.references :rag_flow, null: false, foreign_key: true

      t.string :status, null: false, default: "pending"
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.jsonb :stats, null: false, default: {}
      t.string :triggered_by, null: false, default: "manual"

      t.timestamps
    end

    add_index :rag_runs, [:rag_flow_id, :status]

    create_table :rag_step_runs do |t|
      t.references :rag_run, null: false, foreign_key: true

      t.string :step_type, null: false # source, chunking, embedding, storage
      t.integer :position, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.integer :input_count, null: false, default: 0
      t.integer :output_count, null: false, default: 0
      t.jsonb :stats, null: false, default: {}

      t.timestamps
    end

    add_index :rag_step_runs, [:rag_run_id, :step_type],
              unique: true, name: "idx_step_runs_on_run_and_type"
  end

  def down
    drop_table :rag_step_runs, if_exists: true
    drop_table :rag_runs, if_exists: true
    drop_table :rag_steps_elasticsearch_storages, if_exists: true
    drop_table :rag_steps_sql_database_storages, if_exists: true
    drop_table :rag_steps_llm_embedders, if_exists: true
    drop_table :rag_steps_sentence_chunkers, if_exists: true
    drop_table :rag_steps_markdown_chunkers, if_exists: true
    drop_table :rag_steps_paragraph_chunkers, if_exists: true
    drop_table :rag_steps_fixed_size_chunkers, if_exists: true
    drop_table :rag_steps_elasticsearch_sources, if_exists: true
    drop_table :rag_steps_file_sources, if_exists: true
    drop_table :rag_steps_sql_database_sources, if_exists: true
    drop_table :rag_steps, if_exists: true
    drop_table :rag_flows, if_exists: true
  end
end
