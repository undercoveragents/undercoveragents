# frozen_string_literal: true

# All 4 tool configurator models (SqlQuery, McpServer, RagQuery, RagFlow)
# have been converted to JSONB-backed ActiveModel objects. Their data now
# lives in tools.configuration JSONB column. The separate AR tables are no
# longer used and can be safely dropped.
class DropLegacyToolTypeTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :tools_sql_queries, if_exists: true
    drop_table :tools_mcp_servers, if_exists: true
    drop_table :tools_rag_queries, if_exists: true
    drop_table :tools_rag_flows, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Cannot recreate tools_sql_queries, tools_mcp_servers, tools_rag_queries, tools_rag_flows — " \
          "data now lives in tools.configuration JSONB."
  end
end
