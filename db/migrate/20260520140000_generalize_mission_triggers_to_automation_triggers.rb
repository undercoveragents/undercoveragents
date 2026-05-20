# frozen_string_literal: true

class GeneralizeMissionTriggersToAutomationTriggers < ActiveRecord::Migration[8.1]
  def up
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

    execute <<~SQL.squish
      INSERT INTO automation_triggers (
        id,
        operation_id,
        schedulable_type,
        schedulable_id,
        name,
        trigger_type,
        enabled,
        cron_expression,
        timezone,
        next_run_at,
        payload,
        webhook_secret_digest,
        webhook_secret_prefix,
        last_triggered_at,
        last_error,
        last_result_record_type,
        last_result_record_id,
        created_at,
        updated_at
      )
      SELECT
        mission_triggers.id,
        missions.operation_id,
        'Mission',
        mission_triggers.mission_id,
        mission_triggers.name,
        mission_triggers.trigger_type,
        mission_triggers.enabled,
        mission_triggers.cron_expression,
        mission_triggers.timezone,
        mission_triggers.next_run_at,
        mission_triggers.payload,
        mission_triggers.webhook_secret_digest,
        mission_triggers.webhook_secret_prefix,
        mission_triggers.last_triggered_at,
        mission_triggers.last_error,
        CASE
          WHEN mission_triggers.last_mission_run_id IS NULL THEN NULL
          ELSE 'MissionRun'
        END,
        mission_triggers.last_mission_run_id,
        mission_triggers.created_at,
        mission_triggers.updated_at
      FROM mission_triggers
      INNER JOIN missions ON missions.id = mission_triggers.mission_id
    SQL

    execute <<~SQL.squish
      SELECT setval(
        pg_get_serial_sequence('automation_triggers', 'id'),
        COALESCE((SELECT MAX(id) FROM automation_triggers), 1),
        (SELECT COUNT(*) > 0 FROM automation_triggers)
      )
    SQL

    drop_table :mission_triggers
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Generic automation triggers cannot be safely converted back."
  end
end
