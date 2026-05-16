# frozen_string_literal: true

class AddTelegramChatIdToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :telegram_chat_id, :bigint
    add_column :chats, :user_id, :bigint

    add_index :chats, :telegram_chat_id
    add_index :chats, :user_id
    add_foreign_key :chats, :users, column: :user_id
  end
end
