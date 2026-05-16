# frozen_string_literal: true

class CreateConnectorsVectorDatabases < ActiveRecord::Migration[8.1]
  def change
    create_table :connectors_vector_databases do |t|
      # Connection settings
      t.string :host
      t.integer :port
      t.string :database_name
      t.string :username
      t.string :encrypted_password
      t.boolean :ssl_enabled, null: false, default: false
      t.string :connection_string

      # Table & column settings
      t.string :table_name, null: false
      t.string :embedding_column, null: false, default: "embedding"
      t.string :content_column, null: false, default: "content"
      t.jsonb :metadata_columns, null: false, default: []

      # Embedding settings
      t.integer :embedding_dimensions
      t.string :distance_metric, null: false, default: "cosine"

      # Search settings
      t.integer :top_k, null: false, default: 10
      t.float :similarity_threshold

      # LLM integration
      t.text :llm_instructions

      t.timestamps
    end
  end
end
