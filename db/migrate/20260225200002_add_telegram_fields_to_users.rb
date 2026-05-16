# frozen_string_literal: true

class AddTelegramFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :telegram_user_id, :bigint
    add_column :users, :telegram_username, :string
    add_column :users, :telegram_link_token, :string

    add_index :users, :telegram_user_id, unique: true, where: "telegram_user_id IS NOT NULL"
    add_index :users, :telegram_link_token, unique: true, where: "telegram_link_token IS NOT NULL"
  end
end
