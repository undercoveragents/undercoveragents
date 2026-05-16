class AddDurationMsToMessagesAndToolCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :duration_ms, :integer
    add_column :tool_calls, :duration_ms, :integer
  end
end
