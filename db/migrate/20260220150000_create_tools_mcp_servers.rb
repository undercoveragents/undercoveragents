# frozen_string_literal: true

class CreateToolsMcpServers < ActiveRecord::Migration[8.1]
  def change
    create_table :tools_mcp_servers do |t|
      t.references :connector, null: false, foreign_key: true
      t.jsonb :discovered_tools, null: false, default: []
      t.jsonb :selected_tools, null: false, default: []
      t.datetime :tools_discovered_at
      t.timestamps
    end
  end
end
