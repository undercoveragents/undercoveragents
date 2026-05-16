# frozen_string_literal: true

class CreateConnectors < ActiveRecord::Migration[8.1]
  def change
    create_table :connectors do |t|
      t.string :name, null: false
      t.text :description
      t.string :connectable_type, null: false
      t.bigint :connectable_id, null: false
      t.boolean :enabled, null: false, default: false

      t.timestamps
    end

    add_index :connectors, [:connectable_type, :connectable_id], unique: true
    add_index :connectors, :name, unique: true
    add_index :connectors, :enabled
  end
end
