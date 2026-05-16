# frozen_string_literal: true

class MakePipelineVersionNotNull < ActiveRecord::Migration[8.1]
  def up
    change_column_null :agents, :pipeline_version_id, false
    change_column_null :tools, :pipeline_version_id, false

    # Relax name uniqueness — names must be unique within a pipeline_version, not globally
    remove_index :agents, :name if index_exists?(:agents, :name, unique: true)
    add_index :agents, [:pipeline_version_id, :name], unique: true,
              name: "index_agents_on_pipeline_version_id_and_name"

    remove_index :tools, :name if index_exists?(:tools, :name, unique: true)
    add_index :tools, [:pipeline_version_id, :name], unique: true,
              name: "index_tools_on_pipeline_version_id_and_name"
  end

  def down
    change_column_null :agents, :pipeline_version_id, true
    change_column_null :tools, :pipeline_version_id, true

    remove_index :agents, name: "index_agents_on_pipeline_version_id_and_name" if index_exists?(:agents, name: "index_agents_on_pipeline_version_id_and_name")
    add_index :agents, :name, unique: true unless index_exists?(:agents, :name, unique: true)

    remove_index :tools, name: "index_tools_on_pipeline_version_id_and_name" if index_exists?(:tools, name: "index_tools_on_pipeline_version_id_and_name")
    add_index :tools, :name, unique: true unless index_exists?(:tools, :name, unique: true)
  end
end
