class UnifyTestSuitesAndMissionTests < ActiveRecord::Migration[8.1]
  def up # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
    # ── 1. Extend test_suites ──
    add_column :test_suites, :suite_type, :string, default: "agent", null: false
    add_reference :test_suites, :mission, null: true, foreign_key: true
    change_column_null :test_suites, :agent_id, true

    # ── 2. Extend test_cases ──
    add_column :test_cases, :name, :string
    add_column :test_cases, :input_variables, :jsonb, default: {}, null: false
    add_column :test_cases, :expected_status, :string
    add_column :test_cases, :expected_variables, :jsonb, default: {}, null: false
    change_column_null :test_cases, :prompt, true
    change_column_null :test_cases, :expected_answer, true

    # ── 3. Extend test_case_results ──
    add_column :test_case_results, :actual_status, :string
    add_column :test_case_results, :actual_variables, :jsonb, default: {}, null: false
    add_reference :test_case_results, :mission_run, null: true, foreign_key: true

    # ── 4. Migrate mission test data ──
    migrate_mission_test_data

    # ── 5. Drop old tables (order matters for FKs) ──
    drop_table :mission_test_results
    drop_table :mission_test_runs
    drop_table :mission_test_cases
    drop_table :mission_test_suites
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def migrate_mission_test_data # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
    execute <<~SQL.squish
      INSERT INTO test_suites (name, slug, description, status, suite_type, mission_id, agent_id,
                               generation_temperature, evaluation_temperature, created_at, updated_at)
      SELECT name, slug, description, status, 'mission', mission_id, NULL,
             0.7, 0.7, created_at, updated_at
      FROM mission_test_suites
    SQL

    execute <<~SQL.squish
      INSERT INTO test_cases (name, input_variables, expected_status, expected_variables,
                              match_type, position, test_suite_id, created_at, updated_at)
      SELECT mtc.name, mtc.input_variables, mtc.expected_status, mtc.expected_variables,
             mtc.match_type, mtc.position,
             ts.id,
             mtc.created_at, mtc.updated_at
      FROM mission_test_cases mtc
      INNER JOIN mission_test_suites mts ON mts.id = mtc.mission_test_suite_id
      INNER JOIN test_suites ts ON ts.slug = mts.slug AND ts.suite_type = 'mission'
    SQL

    execute <<~SQL.squish
      INSERT INTO test_suite_runs (status, started_at, completed_at, duration_ms,
                                   passed_count, failed_count, error_count, total_count,
                                   test_suite_id, created_at, updated_at)
      SELECT mtr.status, mtr.started_at, mtr.completed_at, mtr.duration_ms,
             mtr.passed_count, mtr.failed_count, mtr.error_count, mtr.total_count,
             ts.id,
             mtr.created_at, mtr.updated_at
      FROM mission_test_runs mtr
      INNER JOIN mission_test_suites mts ON mts.id = mtr.mission_test_suite_id
      INNER JOIN test_suites ts ON ts.slug = mts.slug AND ts.suite_type = 'mission'
    SQL

    execute <<~SQL.squish
      INSERT INTO test_case_results (status, started_at, completed_at, duration_ms,
                                     passed, analysis, actual_status, actual_variables,
                                     mission_run_id, test_case_id, test_suite_run_id,
                                     created_at, updated_at)
      SELECT mres.status, mres.started_at, mres.completed_at, mres.duration_ms,
             mres.passed, mres.analysis, mres.actual_status, mres.actual_variables,
             mres.mission_run_id,
             tc.id,
             tsr.id,
             mres.created_at, mres.updated_at
      FROM mission_test_results mres
      INNER JOIN mission_test_cases mtc ON mtc.id = mres.mission_test_case_id
      INNER JOIN mission_test_runs mrun ON mrun.id = mres.mission_test_run_id
      INNER JOIN mission_test_suites mts ON mts.id = mrun.mission_test_suite_id
      INNER JOIN test_suites ts ON ts.slug = mts.slug AND ts.suite_type = 'mission'
      INNER JOIN test_cases tc ON tc.test_suite_id = ts.id
                              AND tc.name = mtc.name
                              AND tc.position = mtc.position
      INNER JOIN test_suite_runs tsr ON tsr.test_suite_id = ts.id
                                    AND tsr.created_at = mrun.created_at
    SQL
  end
end
