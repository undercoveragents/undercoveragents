# frozen_string_literal: true

class AddConfigurationToRagSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :rag_steps, :module_type, :string
    add_column :rag_steps, :configuration, :jsonb, null: false, default: {}
  end
end
