class CreateToolsSqlQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :tools_sql_queries do |t|
      t.references :connector, null: false, foreign_key: true
      t.text :custom_instructions
      t.text :context_instructions
      t.jsonb :discovered_schema, default: {}, null: false
      t.jsonb :selected_objects, default: [], null: false
      t.datetime :schema_discovered_at

      t.timestamps
    end
  end
end
