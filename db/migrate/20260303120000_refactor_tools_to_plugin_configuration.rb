# frozen_string_literal: true

class RefactorToolsToPluginConfiguration < ActiveRecord::Migration[8.1]
  CLASS_TO_KEY = {
    "Tools::SqlQuery" => "sql_query",
    "Tools::McpServer" => "mcp_server",
    "Tools::RagQuery" => "rag_query",
    "Tools::RagFlow" => "rag_flow",
  }.freeze

  KEY_TO_CLASS = CLASS_TO_KEY.invert.freeze

  def up
    add_column :tools, :tool_type, :string
    add_column :tools, :configuration, :jsonb, default: {}, null: false

    say_with_time "Backfilling tools.tool_type and tools.configuration" do
      CLASS_TO_KEY.each do |class_name, key|
        execute <<~SQL.squish
          UPDATE tools
          SET tool_type = '#{key}',
              configuration = jsonb_build_object('record_id', toolable_id)
          WHERE toolable_type = '#{class_name}'
        SQL
      end
    end

    change_column_null :tools, :tool_type, false

    remove_index :tools, name: "index_tools_on_toolable_type_and_toolable_id"
    add_index :tools, :tool_type

    remove_column :tools, :toolable_type
    remove_column :tools, :toolable_id
  end

  def down
    add_column :tools, :toolable_type, :string
    add_column :tools, :toolable_id, :bigint

    say_with_time "Backfilling tools.toolable_type and tools.toolable_id" do
      KEY_TO_CLASS.each do |key, class_name|
        execute <<~SQL.squish
          UPDATE tools
          SET toolable_type = '#{class_name}',
              toolable_id = NULLIF(configuration->>'record_id', '')::bigint
          WHERE tool_type = '#{key}'
        SQL
      end
    end

    change_column_null :tools, :toolable_type, false
    change_column_null :tools, :toolable_id, false

    remove_index :tools, :tool_type
    add_index :tools, [:toolable_type, :toolable_id], unique: true

    remove_column :tools, :tool_type
    remove_column :tools, :configuration
  end
end
