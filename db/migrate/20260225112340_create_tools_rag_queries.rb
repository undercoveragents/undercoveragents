class CreateToolsRagQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :tools_rag_queries do |t|
      # ── SQL Database Connector (where chunks/documents live) ──
      t.references :connector, null: false, foreign_key: { to_table: :connectors }

      # ── Tool description ──
      t.text :custom_instructions

      # ── Table configuration ──
      t.string :chunks_table, null: false
      t.string :documents_table, null: false
      t.string :chunk_content_field, null: false, default: "content"
      t.string :embedding_field, null: false, default: "embedding"
      t.string :document_reference_field, null: false, default: "document_id"
      t.jsonb :document_fields, null: false, default: []

      # ── Schema discovery (mirrors SqlQuery pattern) ──
      t.jsonb :discovered_schema, null: false, default: {}
      t.datetime :schema_discovered_at

      # ── Search parameters ──
      t.string :distance_method, null: false, default: "cosine"
      t.float :max_distance, default: 0.8
      t.integer :results_limit, null: false, default: 10

      # ── LLM Connector (for embedding model) ──
      t.references :llm_connector, foreign_key: { to_table: :connectors }
      t.string :embedding_model_id

      t.timestamps
    end
  end
end
