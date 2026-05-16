class RemoveLlmFieldsFromConnectorsSqlDatabases < ActiveRecord::Migration[8.1]
  def change
    remove_column :connectors_sql_databases, :llm_instructions, :text
    remove_column :connectors_sql_databases, :tool_prompt, :text
  end
end
