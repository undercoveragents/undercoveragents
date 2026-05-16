# frozen_string_literal: true

class CreateCapabilities < ActiveRecord::Migration[8.1]
  def change
    create_table :capabilities do |t|
      t.references :agent, null: false, foreign_key: true
      t.boolean :enabled, null: false, default: false
      t.string :capabilitable_type, null: false
      t.bigint :capabilitable_id, null: false
      t.timestamps
    end

    add_index :capabilities, [:capabilitable_type, :capabilitable_id], unique: true
    add_index :capabilities, [:agent_id, :capabilitable_type], unique: true
    add_index :capabilities, :enabled
  end
end
