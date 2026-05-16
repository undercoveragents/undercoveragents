class RemovePipelinesAndPipelineVersions < ActiveRecord::Migration[8.1]
  def up
    # Remove foreign keys first
    remove_foreign_key :agents, :pipeline_versions if foreign_key_exists?(:agents, :pipeline_versions)
    remove_foreign_key :tools, :pipeline_versions if foreign_key_exists?(:tools, :pipeline_versions)
    remove_foreign_key :test_suites, :pipeline_versions if foreign_key_exists?(:test_suites, :pipeline_versions)
    remove_foreign_key :rag_flows, :pipeline_versions if foreign_key_exists?(:rag_flows, :pipeline_versions)
    remove_foreign_key :chats, :pipeline_versions if foreign_key_exists?(:chats, :pipeline_versions)

    # Remove pipeline_version_id columns
    remove_column :agents, :pipeline_version_id if column_exists?(:agents, :pipeline_version_id)
    remove_column :tools, :pipeline_version_id if column_exists?(:tools, :pipeline_version_id)
    remove_column :test_suites, :pipeline_version_id if column_exists?(:test_suites, :pipeline_version_id)
    remove_column :rag_flows, :pipeline_version_id if column_exists?(:rag_flows, :pipeline_version_id)
    remove_column :chats, :pipeline_version_id if column_exists?(:chats, :pipeline_version_id)

    # Deduplicate names/slugs before adding global unique indexes.
    # Keep the most-recently-created record; rename older duplicates.
    %w[agents tools test_suites rag_flows].each do |table|
      execute <<~SQL
        UPDATE #{table} t
        SET name = t.name || ' (' || t.id || ')',
            slug = t.slug || '-' || t.id
        WHERE t.id NOT IN (
          SELECT DISTINCT ON (name) id
          FROM #{table}
          ORDER BY name, id DESC
        )
      SQL
    end

    # Add simple uniqueness indexes (replacing the pipeline_version_id scoped ones)
    add_index :agents, :name, unique: true unless index_exists?(:agents, :name, unique: true)
    add_index :agents, :slug, unique: true unless index_exists?(:agents, :slug, unique: true)
    add_index :tools, :name, unique: true unless index_exists?(:tools, :name, unique: true)
    add_index :tools, :slug, unique: true unless index_exists?(:tools, :slug, unique: true)
    add_index :test_suites, :name, unique: true unless index_exists?(:test_suites, :name, unique: true)
    add_index :test_suites, :slug, unique: true unless index_exists?(:test_suites, :slug, unique: true)
    add_index :rag_flows, :name, unique: true unless index_exists?(:rag_flows, :name, unique: true)
    add_index :rag_flows, :slug, unique: true unless index_exists?(:rag_flows, :slug, unique: true)

    # Drop pipeline tables
    drop_table :pipeline_versions if table_exists?(:pipeline_versions)
    drop_table :pipelines if table_exists?(:pipelines)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
