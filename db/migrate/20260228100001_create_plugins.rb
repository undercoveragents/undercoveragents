# frozen_string_literal: true

class CreatePlugins < ActiveRecord::Migration[8.1]
  def change
    create_table :plugins do |t|
      t.string :identifier, null: false
      t.boolean :enabled, null: false, default: true
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :plugins, :identifier, unique: true
  end
end
