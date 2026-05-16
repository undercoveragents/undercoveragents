# frozen_string_literal: true

class AddBuiltinBehaviorFieldsToTestSuites < ActiveRecord::Migration[8.1]
  def change
    add_test_suite_source_fields
    add_test_case_behavior_fields
    add_test_suite_run_debug_fields
    add_test_case_result_debug_fields
  end

  private

  def add_test_suite_source_fields
    change_table :test_suites, bulk: true do |t|
      t.string :source_type, default: "manual", null: false
      t.jsonb :source_metadata, default: {}, null: false
    end

    add_index :test_suites, :source_type
    add_index :test_suites,
              "(source_metadata ->> 'builtin_key')",
              name: "index_test_suites_on_builtin_key",
              where: "source_type = 'builtin'"
  end

  def add_test_case_behavior_fields
    change_table :test_cases, bulk: true do |t|
      t.string :source_type, default: "manual", null: false
      t.jsonb :source_metadata, default: {}, null: false
      t.string :scenario_key
      t.string :category
      t.string :complexity
      t.string :fixture_key
      t.string :expected_child_builtin_key
      t.jsonb :expected_tool_names, default: [], null: false
      t.boolean :disallow_child_chats, default: false, null: false
      t.jsonb :required_keywords, default: [], null: false
      t.jsonb :forbidden_keywords, default: [], null: false
    end

    add_index :test_cases, :source_type
    add_index :test_cases, :scenario_key
    add_index :test_cases,
              [:test_suite_id, :scenario_key],
              unique: true,
              where: "scenario_key IS NOT NULL",
              name: "index_test_cases_on_suite_and_scenario_key"
  end

  def add_test_suite_run_debug_fields
    change_table :test_suite_runs, bulk: true do |t|
      t.references :user, foreign_key: true
      t.jsonb :debug_snapshot, default: {}, null: false
    end
  end

  def add_test_case_result_debug_fields
    change_table :test_case_results, bulk: true do |t|
      t.jsonb :actual_tool_names, default: [], null: false
      t.jsonb :actual_child_builtin_keys, default: [], null: false
      # rubocop:disable Rails/ThreeStateBooleanColumn
      t.boolean :semantic_passed
      t.boolean :behavior_passed
      # rubocop:enable Rails/ThreeStateBooleanColumn
      t.text :behavior_analysis
      t.jsonb :debug_snapshot, default: {}, null: false
    end
  end
end
