class RenameCustomInstructionsAndRemoveContextInstructionsFromToolsSqlQueries < ActiveRecord::Migration[8.1]
  def change
    rename_column :tools_sql_queries, :custom_instructions, :instructions
    remove_column :tools_sql_queries, :context_instructions, :text
  end
end
