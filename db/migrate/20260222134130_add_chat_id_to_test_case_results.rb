class AddChatIdToTestCaseResults < ActiveRecord::Migration[8.1]
  def change
    add_reference :test_case_results, :chat, null: true, foreign_key: true
  end
end
