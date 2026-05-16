class AddDefaultEmbeddingAndImageModelsToSystemPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :system_preferences, :embedding_connector_id, :bigint
    add_column :system_preferences, :embedding_model_id, :string
    add_column :system_preferences, :image_connector_id, :bigint
    add_column :system_preferences, :image_model_id, :string

    add_foreign_key :system_preferences, :connectors, column: :embedding_connector_id
    add_foreign_key :system_preferences, :connectors, column: :image_connector_id
  end
end
