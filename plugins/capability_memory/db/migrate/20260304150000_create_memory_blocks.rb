# frozen_string_literal: true

class CreateMemoryBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :memory_blocks do |t|
      t.string  :label, null: false
      t.text    :description
      t.text    :value,       null: false, default: ""
      t.integer :char_limit,  null: false, default: 5000
      t.boolean :read_only,   null: false, default: false

      t.timestamps
    end

    add_index :memory_blocks, :label
  end
end
