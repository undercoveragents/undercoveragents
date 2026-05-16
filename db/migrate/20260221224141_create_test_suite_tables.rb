# frozen_string_literal: true

class CreateTestSuiteTables < ActiveRecord::Migration[8.1]
  def change
    create_table :test_suites do |t|
      t.references :pipeline_version, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "active"
      t.string :generation_prompt
      t.timestamps
    end

    add_index :test_suites, [:pipeline_version_id, :name], unique: true

    create_table :test_cases do |t|
      t.references :test_suite, null: false, foreign_key: true
      t.text :prompt, null: false
      t.text :expected_answer, null: false
      t.string :match_type, null: false, default: "semantic"
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :test_cases, [:test_suite_id, :position]

    create_table :test_suite_runs do |t|
      t.references :test_suite, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.integer :passed_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.integer :total_count, null: false, default: 0
      t.integer :duration_ms
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :test_suite_runs, [:test_suite_id, :created_at]
    add_index :test_suite_runs, :status

    create_table :test_case_results do |t|
      t.references :test_suite_run, null: false, foreign_key: true
      t.references :test_case, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.text :actual_answer
      t.boolean :passed
      t.text :analysis
      t.float :score
      t.integer :duration_ms
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :test_case_results, [:test_suite_run_id, :test_case_id], unique: true,
                                                                       name: "idx_test_case_results_on_run_and_case"
    add_index :test_case_results, :status
  end
end
