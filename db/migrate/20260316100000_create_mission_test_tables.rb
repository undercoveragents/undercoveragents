# frozen_string_literal: true

class CreateMissionTestTables < ActiveRecord::Migration[8.0]
  def change
    create_table :mission_test_suites do |t|
      t.references :mission, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :slug
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :mission_test_suites, :name, unique: true
    add_index :mission_test_suites, :slug, unique: true

    create_table :mission_test_cases do |t|
      t.references :mission_test_suite, null: false, foreign_key: true
      t.string :name, null: false
      t.jsonb :input_variables, null: false, default: {}
      t.string :expected_status, null: false, default: "completed"
      t.jsonb :expected_variables, null: false, default: {}
      t.string :match_type, null: false, default: "exact"
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :mission_test_cases, [:mission_test_suite_id, :position]

    create_table :mission_test_runs do |t|
      t.references :mission_test_suite, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.integer :total_count, null: false, default: 0
      t.integer :passed_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.integer :duration_ms
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :mission_test_runs, :status
    add_index :mission_test_runs, [:mission_test_suite_id, :created_at]

    create_table :mission_test_results do |t|
      t.references :mission_test_run, null: false, foreign_key: true
      t.references :mission_test_case, null: false, foreign_key: true
      t.references :mission_run, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :actual_status
      t.jsonb :actual_variables, null: false, default: {}
      t.boolean :passed
      t.text :analysis
      t.integer :duration_ms
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :mission_test_results, [:mission_test_run_id, :mission_test_case_id],
              unique: true, name: "idx_mission_test_results_on_run_and_case"
    add_index :mission_test_results, :status
  end
end
