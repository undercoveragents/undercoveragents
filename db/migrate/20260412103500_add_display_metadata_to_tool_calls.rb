# frozen_string_literal: true

class AddDisplayMetadataToToolCalls < ActiveRecord::Migration[8.0]
  def change
    change_table :tool_calls, bulk: true do |t|
      t.string :display_name
      t.string :icon
    end
  end
end
