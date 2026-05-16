class AddExecutionContextToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :execution_context, :string, default: "playground", null: false
    add_index :chats, :execution_context
  end
end
