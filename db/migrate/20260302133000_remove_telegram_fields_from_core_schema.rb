# frozen_string_literal: true

class RemoveTelegramFieldsFromCoreSchema < ActiveRecord::Migration[8.1]
  def up
    remove_index :connectors, name: :index_connectors_on_telegram_webhook_secret, if_exists: true

    remove_column :users, :telegram_user_id, :bigint if column_exists?(:users, :telegram_user_id)
    remove_column :users, :telegram_username, :string if column_exists?(:users, :telegram_username)
    remove_column :users, :telegram_link_token, :string if column_exists?(:users, :telegram_link_token)

    remove_column :chats, :telegram_chat_id, :bigint if column_exists?(:chats, :telegram_chat_id)
  end

  def down
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

    add_index :connectors,
              "(configuration ->> 'webhook_secret')",
              unique: true,
              where: "connector_type = 'telegram' AND (configuration ->> 'webhook_secret') IS NOT NULL",
              name: :index_connectors_on_telegram_webhook_secret,
              if_not_exists: true
  end
end
