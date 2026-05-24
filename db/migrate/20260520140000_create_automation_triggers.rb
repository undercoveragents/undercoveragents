# frozen_string_literal: true

class CreateAutomationTriggers < ActiveRecord::Migration[8.1]
  def change
    create_table :automation_triggers do |t|
      t.references :operation, null: false, foreign_key: true
      t.string :schedulable_type, null: false
      t.bigint :schedulable_id, null: false
      t.string :name, null: false
      t.string :trigger_type, null: false
      t.boolean :enabled, null: false, default: true
      t.string :cron_expression
      t.string :timezone, null: false, default: "UTC"
      t.datetime :next_run_at
      t.jsonb :payload, null: false, default: {}
      t.string :webhook_secret_digest
      t.string :webhook_secret_prefix
      t.datetime :last_triggered_at
      t.text :last_error
      t.string :last_result_record_type
      t.bigint :last_result_record_id
      t.timestamps
    end

    add_index :automation_triggers, [:schedulable_type, :schedulable_id], name: :index_automation_triggers_on_schedulable
    add_index :automation_triggers,
              [:schedulable_type, :schedulable_id, :name],
              unique: true,
              name: :index_automation_triggers_on_schedulable_and_name
    add_index :automation_triggers,
              [:trigger_type, :enabled, :next_run_at],
              name: :index_automation_triggers_on_schedule_state
    add_index :automation_triggers,
              [:last_result_record_type, :last_result_record_id],
              name: :index_automation_triggers_on_last_result_record
  end
end
