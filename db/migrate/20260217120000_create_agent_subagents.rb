# frozen_string_literal: true

class CreateAgentSubagents < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_subagents do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :subagent, null: false, foreign_key: { to_table: :agents }
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :agent_subagents, [:agent_id, :subagent_id], unique: true
  end
end
