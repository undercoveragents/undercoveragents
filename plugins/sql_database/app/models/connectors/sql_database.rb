# frozen_string_literal: true

module Connectors
  # Configurator for SQL Database connectors.
  # Stores connection details in the Connector's JSONB configuration column.
  class SqlDatabase
    include UndercoverAgents::PluginSystem::Configurator
    include ConnectorPlugin

    ADAPTER_TYPES = ["postgresql", "mysql", "sqlite", "sqlserver", "oracle"].freeze
    DEFAULT_PORTS = {
      "postgresql" => 5432,
      "mysql" => 3306,
      "sqlite" => nil,
      "sqlserver" => 1433,
      "oracle" => 1521,
    }.freeze
    SENSITIVE_FIELDS = [:encrypted_password].freeze
    CONNECTION_FIELDS = [
      "adapter_type", "host", "port", "database_name", "schema_name",
      "username", "encrypted_password", "connection_string", "ssl_enabled",
    ].freeze
    CONFIGURATION_DEFAULTS = {
      "adapter_type" => "postgresql",
      "schema_name" => "public",
      "pool_size" => 5,
      "timeout" => 5000,
      "max_results" => 100,
      "read_only" => true,
      "ssl_enabled" => false,
    }.freeze

    # ── Attributes ────────────────────────────────────────────────

    attribute :adapter_type, :string, default: "postgresql"
    attribute :connection_string, :string
    attribute :database_name, :string
    attribute :encrypted_password, :string
    attribute :host, :string, default: "localhost"
    attribute :max_results, :integer, default: 100
    attribute :pool_size, :integer, default: 5
    attribute :port, :integer
    attribute :read_only, :boolean, default: true
    attribute :schema_name, :string, default: "public"
    attribute :ssl_enabled, :boolean, default: false
    attribute :timeout, :integer, default: 5000
    attribute :username, :string

    # ── Validations ───────────────────────────────────────────────

    validates :adapter_type, presence: true, inclusion: { in: ADAPTER_TYPES }
    validates :host, presence: true, unless: :connection_string?
    validates :database_name, presence: true, unless: :connection_string?
    validates :pool_size, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
    validates :timeout, numericality: { greater_than: 0, less_than_or_equal_to: 60_000 }
    validates :max_results, numericality: { greater_than: 0, less_than_or_equal_to: 10_000 }
    validates :schema_name, presence: true

    # ── Plugin Protocol ───────────────────────────────────────────

    key "sql_database"
    label "SQL Database"
    icon "fa-solid fa-database"
    description "Connect to a relational database (PostgreSQL, MySQL, SQLite, etc.) " \
                "to enable natural language queries over structured data."
    sensitive_keys SENSITIVE_FIELDS

    def self.permitted_params(params)
      params.expect(sql_database: [
                      :adapter_type, :host, :port, :database_name, :schema_name,
                      :username, :encrypted_password, :ssl_enabled, :connection_string,
                      :pool_size, :timeout, :read_only, :max_results,
                    ])
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    def self.param_key = "sql_database"
    def self.list_resources_kind = "sql_database_connectors"
    def self.list_resources_title = "SQL Database Connectors"

    # ── Instance Methods ──────────────────────────────────────────

    def read_only?
      !!read_only
    end

    def ssl_enabled?
      !!ssl_enabled
    end

    def connection_string?
      connection_string.present?
    end

    def default_port
      DEFAULT_PORTS[adapter_type]
    end

    def effective_port
      port || default_port
    end

    def display_host
      if connection_string?
        "(connection string)"
      else
        "#{host}:#{effective_port}/#{database_name}"
      end
    end

    def summary
      "#{adapter_type&.titleize} — #{display_host}"
    end

    # ── Connection Testing ────────────────────────────────────────

    def connection_test_params
      {
        adapter_type:,
        host:,
        port: effective_port,
        database_name:,
        username:,
        ssl_enabled: ssl_enabled?,
        connection_string:,
      }.compact
    end

    def database_discovery_supported?
      ["postgresql", "mysql"].include?(adapter_type)
    end

    # ── Configuration Change Hook ─────────────────────────────────

    def on_configuration_change(connector, old_config, new_config)
      changed = CONNECTION_FIELDS.any? { |f| old_config.to_h[f] != new_config.to_h[f] }
      return unless changed

      Tool.by_type(Tools::SqlQuery.type_key)
          .where("(configuration->>'connector_id')::integer = ?", connector.id)
          .find_each do |tool|
        sql_query = tool.configurator
        next unless sql_query&.schema_discovered?

        sql_query.update!(discovered_schema: {}, schema_discovered_at: nil, selected_objects: [])
      end
    end

    # ── Serialization ─────────────────────────────────────────────

    def to_configuration
      attrs = super
      # Normalize blank credentials
      attrs.delete("encrypted_password") if attrs["encrypted_password"].blank?
      attrs
    end
  end
end
