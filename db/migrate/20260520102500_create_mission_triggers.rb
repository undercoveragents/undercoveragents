# frozen_string_literal: true

class CreateMissionTriggers < ActiveRecord::Migration[8.1]
  def change
    create_table :mission_triggers do |t|
      t.references :mission, null: false, foreign_key: true
      t.references :last_mission_run, foreign_key: { to_table: :mission_runs }
      t.string :name, null: false
      t.string :trigger_type, null: false
      t.boolean :enabled, null: false, default: true
      t.string :cron_expression
      t.string :timezone, null: false, default: "UTC"
      t.jsonb :payload, null: false, default: {}
      t.datetime :next_run_at
      t.datetime :last_triggered_at
      t.string :webhook_secret_prefix
      t.string :webhook_secret_digest
      t.text :last_error

      t.timestamps
    end

    add_index :mission_triggers, [:mission_id, :name], unique: true
    add_index :mission_triggers, [:trigger_type, :enabled, :next_run_at], name: "index_mission_triggers_on_schedule_state"
  end
end