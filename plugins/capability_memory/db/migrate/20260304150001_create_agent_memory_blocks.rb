# frozen_string_literal: true

class CreateAgentMemoryBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_memory_blocks do |t|
      t.references :agent,        null: false, foreign_key: true
      t.references :memory_block, null: false, foreign_key: true

      t.timestamps
    end

    add_index :agent_memory_blocks, [:agent_id, :memory_block_id], unique: true
  end
end
