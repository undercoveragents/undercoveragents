# frozen_string_literal: true

class RemoveSteppableFromRagSteps < ActiveRecord::Migration[8.1]
  def up # rubocop:disable Metrics/MethodLength
    # Remove polymorphic columns from rag_steps
    remove_index :rag_steps, name: "idx_rag_steps_steppable", if_exists: true
    remove_column :rag_steps, :steppable_type
    remove_column :rag_steps, :steppable_id

    # Drop all steppable tables (7 active + 7 placeholder = 14 tables)
    drop_table :rag_steps_sql_database_sources, if_exists: true
    drop_table :rag_steps_fixed_size_chunkers, if_exists: true
    drop_table :rag_steps_paragraph_chunkers, if_exists: true
    drop_table :rag_steps_sentence_chunkers, if_exists: true
    drop_table :rag_steps_markdown_chunkers, if_exists: true
    drop_table :rag_steps_llm_embedders, if_exists: true
    drop_table :rag_steps_sql_database_storages, if_exists: true
    drop_table :rag_steps_file_sources, if_exists: true
    drop_table :rag_steps_elasticsearch_sources, if_exists: true
    drop_table :rag_steps_custom_code_sources, if_exists: true
    drop_table :rag_steps_custom_code_chunkers, if_exists: true
    drop_table :rag_steps_custom_code_embedders, if_exists: true
    drop_table :rag_steps_elasticsearch_storages, if_exists: true
    drop_table :rag_steps_custom_code_storages, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Cannot reverse: steppable tables and data have been dropped. " \
          "Restore from backup or re-run the original creation migrations."
  end
end
