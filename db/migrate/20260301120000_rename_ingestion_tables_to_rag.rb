# frozen_string_literal: true

class RenameIngestionTablesToRag < ActiveRecord::Migration[8.1]
  def up
    rename_table_if_exists(:ingestion_flows, :rag_flows)
    rename_table_if_exists(:ingestion_steps, :rag_steps)
    rename_table_if_exists(:ingestion_runs, :rag_runs)
    rename_table_if_exists(:ingestion_step_runs, :rag_step_runs)

    rename_column_if_exists(:rag_steps, :ingestion_flow_id, :rag_flow_id)
    rename_column_if_exists(:rag_runs, :ingestion_flow_id, :rag_flow_id)
    rename_column_if_exists(:rag_step_runs, :ingestion_run_id, :rag_run_id)
    rename_column_if_exists(:tools_rag_flows, :ingestion_flow_id, :rag_flow_id)

    rename_index_if_exists(:rag_flows, "index_ingestion_flows_on_pipeline_version_id", "index_rag_flows_on_pipeline_version_id")
    rename_index_if_exists(
      :rag_flows,
      "index_ingestion_flows_on_pipeline_version_id_and_name",
      "index_rag_flows_on_pipeline_version_id_and_name",
    )
    rename_index_if_exists(
      :rag_flows,
      "index_ingestion_flows_on_pipeline_version_id_and_slug",
      "index_rag_flows_on_pipeline_version_id_and_slug",
    )

    rename_index_if_exists(:rag_steps, "index_ingestion_steps_on_ingestion_flow_id", "index_rag_steps_on_rag_flow_id")
    rename_index_if_exists(:rag_steps, "idx_ingestion_steps_flow_stage", "idx_rag_steps_flow_stage")

    rename_index_if_exists(:rag_runs, "index_ingestion_runs_on_ingestion_flow_id", "index_rag_runs_on_rag_flow_id")
    rename_index_if_exists(
      :rag_runs,
      "index_ingestion_runs_on_ingestion_flow_id_and_status",
      "index_rag_runs_on_rag_flow_id_and_status",
    )

    rename_index_if_exists(
      :rag_step_runs,
      "index_ingestion_step_runs_on_ingestion_run_id",
      "index_rag_step_runs_on_rag_run_id",
    )

    rename_index_if_exists(
      :tools_rag_flows,
      "index_tools_rag_flows_on_ingestion_flow_id",
      "index_tools_rag_flows_on_rag_flow_id",
    )

    rewire_foreign_key(:rag_steps, :rag_flows, :rag_flow_id, old_column: :ingestion_flow_id)
    rewire_foreign_key(:rag_runs, :rag_flows, :rag_flow_id, old_column: :ingestion_flow_id)
    rewire_foreign_key(:rag_step_runs, :rag_runs, :rag_run_id, old_column: :ingestion_run_id)
    rewire_foreign_key(:tools_rag_flows, :rag_flows, :rag_flow_id, old_column: :ingestion_flow_id)
  end

  def down
    rewire_foreign_key(:tools_rag_flows, :ingestion_flows, :ingestion_flow_id, old_column: :rag_flow_id)
    rewire_foreign_key(:rag_step_runs, :ingestion_runs, :ingestion_run_id, old_column: :rag_run_id)
    rewire_foreign_key(:rag_runs, :ingestion_flows, :ingestion_flow_id, old_column: :rag_flow_id)
    rewire_foreign_key(:rag_steps, :ingestion_flows, :ingestion_flow_id, old_column: :rag_flow_id)

    rename_index_if_exists(
      :tools_rag_flows,
      "index_tools_rag_flows_on_rag_flow_id",
      "index_tools_rag_flows_on_ingestion_flow_id",
    )

    rename_index_if_exists(
      :rag_step_runs,
      "index_rag_step_runs_on_rag_run_id",
      "index_ingestion_step_runs_on_ingestion_run_id",
    )

    rename_index_if_exists(
      :rag_runs,
      "index_rag_runs_on_rag_flow_id_and_status",
      "index_ingestion_runs_on_ingestion_flow_id_and_status",
    )
    rename_index_if_exists(:rag_runs, "index_rag_runs_on_rag_flow_id", "index_ingestion_runs_on_ingestion_flow_id")

    rename_index_if_exists(:rag_steps, "idx_rag_steps_flow_stage", "idx_ingestion_steps_flow_stage")
    rename_index_if_exists(:rag_steps, "index_rag_steps_on_rag_flow_id", "index_ingestion_steps_on_ingestion_flow_id")

    rename_index_if_exists(
      :rag_flows,
      "index_rag_flows_on_pipeline_version_id_and_slug",
      "index_ingestion_flows_on_pipeline_version_id_and_slug",
    )
    rename_index_if_exists(
      :rag_flows,
      "index_rag_flows_on_pipeline_version_id_and_name",
      "index_ingestion_flows_on_pipeline_version_id_and_name",
    )
    rename_index_if_exists(:rag_flows, "index_rag_flows_on_pipeline_version_id", "index_ingestion_flows_on_pipeline_version_id")

    rename_column_if_exists(:tools_rag_flows, :rag_flow_id, :ingestion_flow_id)
    rename_column_if_exists(:rag_step_runs, :rag_run_id, :ingestion_run_id)
    rename_column_if_exists(:rag_runs, :rag_flow_id, :ingestion_flow_id)
    rename_column_if_exists(:rag_steps, :rag_flow_id, :ingestion_flow_id)

    rename_table_if_exists(:rag_step_runs, :ingestion_step_runs)
    rename_table_if_exists(:rag_runs, :ingestion_runs)
    rename_table_if_exists(:rag_steps, :ingestion_steps)
    rename_table_if_exists(:rag_flows, :ingestion_flows)
  end

  private

  def rename_table_if_exists(from, to)
    return unless table_exists?(from)
    return if table_exists?(to)

    rename_table(from, to)
  end

  def rename_column_if_exists(table, from, to)
    return unless table_exists?(table)
    return unless column_exists?(table, from)
    return if column_exists?(table, to)

    rename_column(table, from, to)
  end

  def rename_index_if_exists(table, from, to)
    return unless table_exists?(table)
    return unless index_name_exists?(table, from)
    return if index_name_exists?(table, to)

    rename_index(table, from, to)
  end

  def rewire_foreign_key(from_table, to_table, to_column, old_column:)
    return unless table_exists?(from_table)

    remove_foreign_key(from_table, column: old_column) if column_exists?(from_table, old_column)
    remove_foreign_key(from_table, column: to_column) if column_exists?(from_table, to_column)

    return unless column_exists?(from_table, to_column)
    return unless table_exists?(to_table)

    add_foreign_key(from_table, to_table, column: to_column)
  end
end
