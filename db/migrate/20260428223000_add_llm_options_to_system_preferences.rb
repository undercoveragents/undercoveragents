# frozen_string_literal: true

class AddLlmOptionsToSystemPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :system_preferences, :temperature, :float
    add_column :system_preferences, :thinking_effort, :string
    add_column :system_preferences, :thinking_budget, :integer
    add_column :system_preferences, :custom_llm_params, :jsonb, default: {}, null: false
  end
end
