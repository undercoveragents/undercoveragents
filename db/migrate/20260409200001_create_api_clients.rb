# frozen_string_literal: true

class CreateApiClients < ActiveRecord::Migration[8.1]
  def change
    create_table :api_clients do |t|
      t.string :name, null: false
      t.text :description
      t.string :token_prefix, null: false
      t.string :token_digest, null: false
      t.string :access_scope, null: false, default: "all"
      t.boolean :enabled, null: false, default: true
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :api_clients, :name, unique: true
    add_index :api_clients, :token_prefix, unique: true
    add_index :api_clients, :enabled
  end
end
