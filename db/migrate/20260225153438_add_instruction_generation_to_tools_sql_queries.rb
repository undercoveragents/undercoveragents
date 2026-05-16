class AddInstructionGenerationToToolsSqlQueries < ActiveRecord::Migration[8.1]
  def change
    add_column :tools_sql_queries, :instruction_generation_status, :string
    add_column :tools_sql_queries, :instruction_generation_started_at, :datetime
    add_column :tools_sql_queries, :instruction_generation_completed_at, :datetime
    add_column :tools_sql_queries, :instruction_generation_error, :text
  end
end
