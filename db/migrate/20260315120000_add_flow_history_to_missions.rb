# frozen_string_literal: true

class AddFlowHistoryToMissions < ActiveRecord::Migration[8.1]
  def change
    add_column :missions, :flow_undo_history, :jsonb, default: [], null: false
    add_column :missions, :flow_redo_history, :jsonb, default: [], null: false
  end
end
