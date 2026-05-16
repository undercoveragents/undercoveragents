# frozen_string_literal: true

module ConnectorsHelper
  SQL_DATABASE_CONNECTOR_ADAPTER_LABELS = {
    "postgresql" => "PostgreSQL",
    "mysql" => "MySQL",
    "sqlite" => "SQLite",
  }.freeze

  SQL_DATABASE_CONNECTOR_WIZARD_STEPS = [
    { label: "Name it", target_id: "sql-connector-step-identity" },
    { label: "Connect", target_id: "sql-connector-step-connect" },
    { label: "Defaults", target_id: "sql-connector-step-defaults" },
    { label: "Verify", target_id: "sql-connector-step-verify" },
  ].freeze

  def connector_type_label(connector)
    connector.type_label
  end

  def connector_type_icon(connector)
    connector.type_icon
  end

  def transport_type_label(transport_type)
    case transport_type
    when "stdio" then "STDIO (Local Command)"
    when "sse" then "SSE (Server-Sent Events)"
    when "streamable_http" then "Streamable HTTP"
    else transport_type.to_s.titleize
    end
  end

  def connector_status_label(connector)
    connector.enabled? ? "Active" : "Inactive"
  end

  def connector_status_color(connector)
    connector.enabled? ? "success" : "warning"
  end

  def connector_status_badge(connector)
    label = connector_status_label(connector)
    color = connector_status_color(connector)
    content_tag(:span, label, class: "badge badge-#{color}")
  end

  def sql_database_connector_form_state(connector)
    selected_database = connector.database_name.to_s.presence
    connection_mode = sql_database_connection_mode(connector)

    {
      action: connector.persisted? ? admin_connector_path(connector) : admin_connectors_path,
      method: connector.persisted? ? :patch : :post,
      selected_database:,
      database_options: sql_database_database_options(selected_database),
      connection_mode:,
      auto_load_databases: sql_database_auto_load_databases?(connector, connection_mode),
      stylesheet_urls: sql_database_connector_stylesheet_urls,
      adapter_options: sql_database_connector_adapter_options(connector),
      wizard: sql_database_connector_wizard(connector),
    }
  end

  def sql_database_connection_mode(connector)
    connector.connection_string? ? "connection_string" : "fields"
  end

  def sql_database_database_options(selected_database)
    return [] if selected_database.blank?

    [[selected_database, selected_database]]
  end

  def sql_database_auto_load_databases?(connector, connection_mode)
    connector.persisted? &&
      connection_mode == "fields" &&
      connector.database_discovery_supported? &&
      connector.host.present? &&
      connector.database_name.present?
  end

  def sql_database_connector_stylesheet_urls
    [
      asset_path("plugin_sql_database_wizard.css"),
      asset_path("plugin_sql_database_connector_wizard.css"),
    ]
  end

  def sql_database_connector_adapter_options(connector)
    options_for_select(
      SQL_DATABASE_CONNECTOR_ADAPTER_LABELS.map { |adapter, label| [label, adapter] },
      connector.adapter_type,
    )
  end

  def sql_database_connector_wizard(connector)
    build_wizard_component(
      eyebrow: "SQL Database",
      title: connector.persisted? ? "Refine connector settings" : "Create a SQL connector",
      subtitle: [
        "Name the connector, choose how to authenticate, load the database catalog,",
        "and verify the connection before saving.",
      ].join(" "),
      steps: SQL_DATABASE_CONNECTOR_WIZARD_STEPS,
    )
  end
end
