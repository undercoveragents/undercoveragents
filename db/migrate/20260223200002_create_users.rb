# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest
      t.string :role, null: false, default: "user"
      t.string :status, null: false, default: "active"
      t.string :provider
      t.string :uid

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, [:provider, :uid], unique: true, where: "provider IS NOT NULL"
    add_index :users, :role
  end
end
