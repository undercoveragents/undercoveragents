class CreateConnectorsMcpServers < ActiveRecord::Migration[8.1]
  def change
    create_table :connectors_mcp_servers do |t|
      # Transport type: stdio, sse, streamable_http
      t.string :transport_type, null: false, default: "stdio"

      # STDIO transport fields
      t.string :command
      t.jsonb :args, default: [], null: false
      t.jsonb :env_vars, default: {}, null: false

      # SSE / Streamable HTTP transport fields
      t.string :url
      t.jsonb :headers, default: {}, null: false
      t.string :http_version

      # OAuth configuration (SSE / Streamable HTTP)
      t.boolean :oauth_enabled, default: false, null: false
      t.string :oauth_client_id
      t.string :oauth_client_secret
      t.string :oauth_issuer
      t.string :oauth_scope
      t.string :oauth_redirect_uri
      t.string :oauth_grant_type

      # Connection settings
      t.integer :request_timeout, default: 8000, null: false

      t.timestamps
    end
  end
end
