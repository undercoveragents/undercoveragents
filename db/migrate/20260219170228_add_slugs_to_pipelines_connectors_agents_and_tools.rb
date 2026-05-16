class AddSlugsToPipelinesConnectorsAgentsAndTools < ActiveRecord::Migration[8.1]
  def up
    # Add slug columns (nullable first, so we can populate before indexing)
    add_column :pipelines, :slug, :string
    add_column :connectors, :slug, :string
    add_column :agents, :slug, :string
    add_column :tools, :slug, :string

    # Populate slugs for existing records using name → parameterize
    execute <<~SQL.squish
      UPDATE pipelines SET slug = LOWER(REPLACE(REPLACE(TRIM(name), ' ', '-'), '''', ''))
      WHERE slug IS NULL OR slug = ''
    SQL

    execute <<~SQL.squish
      UPDATE connectors SET slug = LOWER(REPLACE(REPLACE(TRIM(name), ' ', '-'), '''', ''))
      WHERE slug IS NULL OR slug = ''
    SQL

    execute <<~SQL.squish
      UPDATE agents SET slug = LOWER(REPLACE(REPLACE(TRIM(name), ' ', '-'), '''', ''))
      WHERE slug IS NULL OR slug = ''
    SQL

    execute <<~SQL.squish
      UPDATE tools SET slug = LOWER(REPLACE(REPLACE(TRIM(name), ' ', '-'), '''', ''))
      WHERE slug IS NULL OR slug = ''
    SQL

    # Now enforce NOT NULL
    change_column_null :pipelines, :slug, false
    change_column_null :connectors, :slug, false
    change_column_null :agents, :slug, false
    change_column_null :tools, :slug, false

    # Add unique indexes
    add_index :pipelines, :slug, unique: true
    add_index :connectors, :slug, unique: true
    add_index :agents, [:pipeline_version_id, :slug], unique: true,
              name: "index_agents_on_pipeline_version_id_and_slug"
    add_index :tools, [:pipeline_version_id, :slug], unique: true,
              name: "index_tools_on_pipeline_version_id_and_slug"
  end

  def down
    remove_index :tools, name: "index_tools_on_pipeline_version_id_and_slug"
    remove_index :agents, name: "index_agents_on_pipeline_version_id_and_slug"
    remove_index :connectors, :slug
    remove_index :pipelines, :slug

    remove_column :tools, :slug
    remove_column :agents, :slug
    remove_column :connectors, :slug
    remove_column :pipelines, :slug
  end
end
