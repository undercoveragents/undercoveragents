class AddLlmConfigToToolsSqlQueries < ActiveRecord::Migration[8.1]
  def change
    add_column :tools_sql_queries, :llm_config_source, :string, null: false, default: "inherit"
    add_column :tools_sql_queries, :llm_connector_id, :bigint
    add_column :tools_sql_queries, :model_id, :string
    add_column :tools_sql_queries, :temperature, :float

    add_index :tools_sql_queries, :llm_connector_id
    add_foreign_key :tools_sql_queries, :connectors, column: :llm_connector_id
  end
end
