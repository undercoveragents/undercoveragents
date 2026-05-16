class RemoveSchemaFieldsFromSqlDatabasesAndDropAgentConnectors < ActiveRecord::Migration[8.1]
  def change
    remove_column :connectors_sql_databases, :discovered_schema, :jsonb, default: {}, null: false
    remove_column :connectors_sql_databases, :selected_objects, :jsonb, default: [], null: false
    remove_column :connectors_sql_databases, :schema_discovered_at, :datetime

    drop_table :agent_connectors do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :connector, null: false, foreign_key: true
      t.integer :position, default: 0, null: false
      t.timestamps
    end
  end
end
