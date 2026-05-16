class RenameConnectableTypeToConnectorType < ActiveRecord::Migration[8.1]
  def up
    # Add new column
    add_column :connectors, :connector_type, :string

    # Migrate data: convert STI class names to short keys
    execute <<~SQL
      UPDATE connectors SET connector_type = CASE connectable_type
        WHEN 'Connectors::SqlDatabase' THEN 'sql_database'
        WHEN 'Connectors::LlmProvider' THEN 'llm_provider'
        WHEN 'Connectors::McpServer' THEN 'mcp_server'
        WHEN 'Connectors::Authentication' THEN 'authentication'
        WHEN 'Connectors::Telegram' THEN 'telegram'
        ELSE lower(replace(split_part(connectable_type, '::', 2), '::', '_'))
      END
    SQL

    # Make NOT NULL
    change_column_null :connectors, :connector_type, false

    # Drop the old unique partial index on webhook_secret (references connectable_type)
    remove_index :connectors, name: :index_connectors_on_telegram_webhook_secret, if_exists: true

    # Remove old column
    remove_column :connectors, :connectable_type

    # Add new unique partial index using connector_type
    add_index :connectors, "(configuration ->> 'webhook_secret')",
              unique: true,
              where: "connector_type = 'telegram' AND (configuration ->> 'webhook_secret') IS NOT NULL",
              name: :index_connectors_on_telegram_webhook_secret

    # Add index on connector_type
    add_index :connectors, :connector_type
  end

  def down
    add_column :connectors, :connectable_type, :string

    execute <<~SQL
      UPDATE connectors SET connectable_type = CASE connector_type
        WHEN 'sql_database' THEN 'Connectors::SqlDatabase'
        WHEN 'llm_provider' THEN 'Connectors::LlmProvider'
        WHEN 'mcp_server' THEN 'Connectors::McpServer'
        WHEN 'authentication' THEN 'Connectors::Authentication'
        WHEN 'telegram' THEN 'Connectors::Telegram'
        ELSE 'Connectors::' || initcap(replace(connector_type, '_', ''))
      END
    SQL

    change_column_null :connectors, :connectable_type, false

    remove_index :connectors, name: :index_connectors_on_telegram_webhook_secret, if_exists: true
    remove_column :connectors, :connector_type

    add_index :connectors, "(configuration ->> 'webhook_secret')",
              unique: true,
              where: "connectable_type = 'Connectors::Telegram' AND (configuration ->> 'webhook_secret') IS NOT NULL",
              name: :index_connectors_on_telegram_webhook_secret
  end
end
