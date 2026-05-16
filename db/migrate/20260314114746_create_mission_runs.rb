# frozen_string_literal: true

class CreateMissionRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :mission_runs do |t|
      t.references :mission, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.jsonb :flow_snapshot, null: false, default: {}
      t.jsonb :variables, null: false, default: {}
      t.jsonb :execution_state, null: false, default: {}
      t.string :current_node_id
      t.text :error
      t.jsonb :trigger_data, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :mission_runs, :status
    add_index :mission_runs, [:mission_id, :status]
  end
end
