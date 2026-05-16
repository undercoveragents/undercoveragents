# frozen_string_literal: true

class AddTelegramFieldsToUsersAndChats < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :telegram_user_id, :bigint unless column_exists?(:users, :telegram_user_id)
    add_column :users, :telegram_username, :string unless column_exists?(:users, :telegram_username)
    add_column :users, :telegram_link_token, :string unless column_exists?(:users, :telegram_link_token)

    add_index :users,
              :telegram_user_id,
              unique: true,
              where: "telegram_user_id IS NOT NULL",
              if_not_exists: true
    add_index :users,
              :telegram_link_token,
              unique: true,
              where: "telegram_link_token IS NOT NULL",
              if_not_exists: true

    add_column :chats, :telegram_chat_id, :bigint unless column_exists?(:chats, :telegram_chat_id)
    add_index :chats, :telegram_chat_id, if_not_exists: true
  end

  def down
    remove_column :chats, :telegram_chat_id, :bigint if column_exists?(:chats, :telegram_chat_id)

    remove_column :users, :telegram_link_token, :string if column_exists?(:users, :telegram_link_token)
    remove_column :users, :telegram_username, :string if column_exists?(:users, :telegram_username)
    remove_column :users, :telegram_user_id, :bigint if column_exists?(:users, :telegram_user_id)
  end
end
