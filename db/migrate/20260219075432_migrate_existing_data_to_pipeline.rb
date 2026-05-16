# frozen_string_literal: true

class MigrateExistingDataToPipeline < ActiveRecord::Migration[8.1]
  def up
    # Only run if there are existing agents or tools without a pipeline_version_id
    agents_need_migration = execute("SELECT COUNT(*) FROM agents WHERE pipeline_version_id IS NULL").first["count"].to_i
    tools_need_migration = execute("SELECT COUNT(*) FROM tools WHERE pipeline_version_id IS NULL").first["count"].to_i

    return unless agents_need_migration.positive? || tools_need_migration.positive?

    # Create the default pipeline
    execute <<~SQL
      INSERT INTO pipelines (name, description, created_at, updated_at)
      VALUES ('Default Pipeline', 'Auto-created pipeline for existing agents and tools', NOW(), NOW())
    SQL

    pipeline_id = execute("SELECT id FROM pipelines WHERE name = 'Default Pipeline' LIMIT 1").first["id"]

    # Create v1 as published
    execute <<~SQL
      INSERT INTO pipeline_versions (pipeline_id, version_number, status, published_at, created_at, updated_at)
      VALUES (#{pipeline_id}, 1, 'published', NOW(), NOW(), NOW())
    SQL

    version_id = execute(
      "SELECT id FROM pipeline_versions WHERE pipeline_id = #{pipeline_id} AND version_number = 1 LIMIT 1",
    ).first["id"]

    # Associate all existing agents and tools to v1
    execute("UPDATE agents SET pipeline_version_id = #{version_id} WHERE pipeline_version_id IS NULL")
    execute("UPDATE tools SET pipeline_version_id = #{version_id} WHERE pipeline_version_id IS NULL")
  end

  def down
    # Remove pipeline_version_id from agents and tools
    execute("UPDATE agents SET pipeline_version_id = NULL")
    execute("UPDATE tools SET pipeline_version_id = NULL")

    # Clean up pipeline data
    execute("DELETE FROM pipeline_versions")
    execute("DELETE FROM pipelines WHERE name = 'Default Pipeline'")
  end
end
