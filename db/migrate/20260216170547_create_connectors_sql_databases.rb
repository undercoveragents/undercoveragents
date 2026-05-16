# frozen_string_literal: true

class CreateConnectorsSqlDatabases < ActiveRecord::Migration[8.1]
  def change
    create_table :connectors_sql_databases do |t|
      # Connection settings
      t.string :adapter_type, null: false, default: "postgresql"
      t.string :host
      t.integer :port
      t.string :database_name
      t.string :schema_name, default: "public"
      t.string :username
      t.string :encrypted_password
      t.boolean :ssl_enabled, null: false, default: false
      t.string :connection_string

      # Pool & timeout settings
      t.integer :pool_size, null: false, default: 5
      t.integer :timeout, null: false, default: 5000

      # Query settings
      t.boolean :read_only, null: false, default: true
      t.integer :max_results, null: false, default: 100

      # LLM integration
      t.text :llm_instructions

      # Schema discovery cache
      t.jsonb :discovered_schema, null: false, default: {}
      t.jsonb :selected_objects, null: false, default: []
      t.datetime :schema_discovered_at

      t.timestamps
    end
  end
end
