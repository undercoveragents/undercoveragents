# frozen_string_literal: true

class AddCounterCachesToChats < ActiveRecord::Migration[8.1]
  def up
    add_column :chats, :messages_count, :integer, null: false, default: 0
    add_column :chats, :child_chats_count, :integer, null: false, default: 0

    execute <<~SQL
      UPDATE chats
         SET messages_count = (
               SELECT COUNT(*) FROM messages WHERE messages.chat_id = chats.id
             )
    SQL

    execute <<~SQL
      UPDATE chats
         SET child_chats_count = (
               SELECT COUNT(*) FROM chats AS children
                WHERE children.parent_chat_id = chats.id
             )
    SQL
  end

  def down
    remove_column :chats, :messages_count
    remove_column :chats, :child_chats_count
  end
end
