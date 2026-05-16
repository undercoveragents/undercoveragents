# frozen_string_literal: true

class CreatePipelineVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :pipeline_versions do |t|
      t.references :pipeline, null: false, foreign_key: true, index: true
      t.integer :version_number, null: false
      t.string :status, null: false, default: "draft"
      t.references :parent_version, null: true, foreign_key: { to_table: :pipeline_versions }
      t.jsonb :compiled_payload
      t.datetime :published_at

      t.timestamps
    end

    # version_number must be unique per pipeline
    add_index :pipeline_versions, [:pipeline_id, :version_number], unique: true

    # Only ONE published version per pipeline (partial unique index)
    add_index :pipeline_versions, :pipeline_id,
              unique: true,
              where: "status = 'published'",
              name: "index_pipeline_versions_one_published_per_pipeline"
  end
end
