# frozen_string_literal: true

class CreateClients < ActiveRecord::Migration[8.0]
  def change
    create_table :clients do |t|
      t.string :name, null: false
      t.text :title
      t.text :welcome_message
      t.text :footer
      t.boolean :default, null: false, default: false
      t.references :agent, null: false, foreign_key: true

      t.timestamps
    end

    add_index :clients, :default
    add_index :clients, :name, unique: true
  end
end
