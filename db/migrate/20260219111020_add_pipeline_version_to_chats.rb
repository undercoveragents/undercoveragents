class AddPipelineVersionToChats < ActiveRecord::Migration[8.1]
  def change
    add_reference :chats, :pipeline_version, null: true, foreign_key: true
  end
end
