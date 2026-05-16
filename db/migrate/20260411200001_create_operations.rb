# frozen_string_literal: true

class CreateOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :operations do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :icon, default: "fa-solid fa-briefcase"
      t.boolean :system, default: false, null: false

      t.timestamps
    end

    add_index :operations, :name, unique: true
    add_index :operations, :slug, unique: true
    add_index :operations, :system
  end
end
