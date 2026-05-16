class AddToolPromptToConnectorsSqlDatabases < ActiveRecord::Migration[8.1]
  def change
    add_column :connectors_sql_databases, :tool_prompt, :text
  end
end
