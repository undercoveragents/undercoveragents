class AddLlmFieldsAndSlugToTestSuites < ActiveRecord::Migration[8.1]
  def change
    change_table :test_suites, bulk: true do |t|
      t.bigint :generation_llm_connector_id
      t.string :generation_model_id
      t.float :generation_temperature, default: 0.7, null: false
      t.bigint :evaluation_llm_connector_id
      t.string :evaluation_model_id
      t.float :evaluation_temperature, default: 0.7, null: false
      t.string :slug
    end

    add_index :test_suites, :generation_llm_connector_id
    add_index :test_suites, :evaluation_llm_connector_id
    add_index :test_suites, %i[pipeline_version_id slug], unique: true

    add_foreign_key :test_suites, :connectors, column: :generation_llm_connector_id
    add_foreign_key :test_suites, :connectors, column: :evaluation_llm_connector_id
  end
end
