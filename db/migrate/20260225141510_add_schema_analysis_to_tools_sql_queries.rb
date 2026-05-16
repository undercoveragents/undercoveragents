class AddSchemaAnalysisToToolsSqlQueries < ActiveRecord::Migration[8.1]
  def change
    add_column :tools_sql_queries, :enhanced_description, :text
    add_column :tools_sql_queries, :schema_analysis_status, :string
    add_column :tools_sql_queries, :schema_analysis_started_at, :datetime
    add_column :tools_sql_queries, :schema_analysis_completed_at, :datetime
    add_column :tools_sql_queries, :schema_analysis_error, :text
    add_column :tools_sql_queries, :schema_analysis_model_id, :string
    add_column :tools_sql_queries, :schema_analysis_llm_connector_id, :bigint

    add_index :tools_sql_queries, :schema_analysis_llm_connector_id,
              name: "index_tools_sql_queries_on_schema_analysis_llm_connector_id"
    add_foreign_key :tools_sql_queries, :connectors, column: :schema_analysis_llm_connector_id
  end
end
