class AddPlaygroundFieldsToChats < ActiveRecord::Migration[8.1]
  def change
    add_reference :chats, :agent, null: true, foreign_key: true
    add_column :chats, :title, :string
    add_column :chats, :status, :string, default: "idle", null: false
  end
end
