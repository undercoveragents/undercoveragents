# frozen_string_literal: true

class RemoveGenerationFieldsFromTestSuites < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :test_suites, column: :generation_llm_connector_id
    remove_index :test_suites, :generation_llm_connector_id

    remove_column :test_suites, :generation_llm_connector_id, :bigint
    remove_column :test_suites, :generation_model_id, :string
    remove_column :test_suites, :generation_prompt, :string
    remove_column :test_suites, :generation_temperature, :float
  end
end