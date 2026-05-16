# frozen_string_literal: true

class UnifyConnectorsIntoSingleTable < ActiveRecord::Migration[8.1]
  def up
    add_column :connectors, :configuration, :jsonb, default: {}, null: false

    execute <<~SQL
      UPDATE connectors AS c
      SET configuration = jsonb_strip_nulls(
        jsonb_build_object(
          'adapter_type', s.adapter_type,
          'host', s.host,
          'port', s.port,
          'database_name', s.database_name,
          'schema_name', s.schema_name,
          'username', s.username,
          'encrypted_password', s.encrypted_password,
          'ssl_enabled', s.ssl_enabled,
          'connection_string', s.connection_string,
          'pool_size', s.pool_size,
          'timeout', s.timeout,
          'read_only', s.read_only,
          'max_results', s.max_results
        )
      )
      FROM connectors_sql_databases AS s
      WHERE c.connectable_type = 'Connectors::SqlDatabase' AND c.connectable_id = s.id
    SQL

    execute <<~SQL
      UPDATE connectors AS c
      SET configuration = jsonb_strip_nulls(
        jsonb_build_object(
          'provider', l.provider,
          'api_key', l.api_key,
          'api_base', l.api_base,
          'organization_id', l.organization_id,
          'project_id', l.project_id,
          'secret_key', l.secret_key,
          'region', l.region,
          'session_token', l.session_token,
          'auth_token', l.auth_token,
          'use_system_role', l.use_system_role,
          'http_proxy', l.http_proxy,
          'request_timeout', l.request_timeout,
          'max_retries', l.max_retries,
          'retry_interval', l.retry_interval,
          'retry_backoff_factor', l.retry_backoff_factor,
          'retry_interval_randomness', l.retry_interval_randomness
        )
      )
      FROM connectors_llm_providers AS l
      WHERE c.connectable_type = 'Connectors::LlmProvider' AND c.connectable_id = l.id
    SQL

    execute <<~SQL
      UPDATE connectors AS c
      SET configuration = jsonb_strip_nulls(
        jsonb_build_object(
          'transport_type', m.transport_type,
          'command', m.command,
          'args', m.args,
          'env_vars', m.env_vars,
          'url', m.url,
          'headers', m.headers,
          'http_version', m.http_version,
          'oauth_enabled', m.oauth_enabled,
          'oauth_client_id', m.oauth_client_id,
          'oauth_client_secret', m.oauth_client_secret,
          'oauth_issuer', m.oauth_issuer,
          'oauth_scope', m.oauth_scope,
          'oauth_redirect_uri', m.oauth_redirect_uri,
          'oauth_grant_type', m.oauth_grant_type,
          'request_timeout', m.request_timeout
        )
      )
      FROM connectors_mcp_servers AS m
      WHERE c.connectable_type = 'Connectors::McpServer' AND c.connectable_id = m.id
    SQL

    execute <<~SQL
      UPDATE connectors AS c
      SET configuration = jsonb_strip_nulls(
        jsonb_build_object(
          'provider', a.provider,
          'site_url', a.site_url,
          'realm', a.realm,
          'client_id', a.client_id,
          'client_secret', a.client_secret
        )
      )
      FROM connectors_authentications AS a
      WHERE c.connectable_type = 'Connectors::Authentication' AND c.connectable_id = a.id
    SQL

    execute <<~SQL
      UPDATE connectors AS c
      SET configuration = jsonb_strip_nulls(
        jsonb_build_object(
          'bot_token', t.bot_token,
          'bot_username', t.bot_username,
          'webhook_url', t.webhook_url,
          'webhook_secret', t.webhook_secret
        )
      )
      FROM connectors_telegrams AS t
      WHERE c.connectable_type = 'Connectors::Telegram' AND c.connectable_id = t.id
    SQL

    remove_index :connectors, name: :index_connectors_on_connectable_type_and_connectable_id
    remove_column :connectors, :connectable_id

    add_index :connectors,
              "(configuration->>'webhook_secret')",
              unique: true,
              where: "connectable_type = 'Connectors::Telegram' AND configuration->>'webhook_secret' IS NOT NULL",
              name: :index_connectors_on_telegram_webhook_secret

    drop_table :connectors_sql_databases
    drop_table :connectors_llm_providers
    drop_table :connectors_mcp_servers
    drop_table :connectors_authentications
    drop_table :connectors_telegrams
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Connector storage has been unified into connectors.configuration"
  end
end
