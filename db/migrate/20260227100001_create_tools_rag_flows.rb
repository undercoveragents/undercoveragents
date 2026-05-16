# frozen_string_literal: true

class CreateToolsRagFlows < ActiveRecord::Migration[8.1]
  def change
    create_table :tools_rag_flows do |t|
      t.references :rag_flow, null: false, foreign_key: true
      t.text :custom_instructions
      t.jsonb :document_fields, null: false, default: []
      t.string :distance_method, null: false, default: "cosine"
      t.float :max_distance, default: 0.8
      t.integer :results_limit, null: false, default: 10

      t.timestamps
    end
  end
end
