class CreateSystemPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :system_preferences do |t|
      t.bigint :llm_connector_id
      t.string :model_id

      t.timestamps
    end

    add_foreign_key :system_preferences, :connectors, column: :llm_connector_id
  end
end
