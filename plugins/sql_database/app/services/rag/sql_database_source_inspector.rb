# frozen_string_literal: true

module Rag
  class SqlDatabaseSourceInspector
    include SqlConnectionConfigBuilder
    include SqlErrorSanitizer

    Result = Data.define(:success?, :message, :objects, :columns)

    def initialize(connector)
      @connector = connector
    end

    def schema_options
      return failure(connector_error) if connector_error

      discovery = Tools::SchemaDiscoverer.new(@connector).call
      return failure(discovery.message) unless discovery.success?

      objects = Array(discovery.schema&.dig("objects")).map do |object|
        {
          "name" => object["name"],
          "type" => object["type"],
          "columns" => normalize_columns(object["columns"]),
        }
      end

      success(message: "Loaded #{objects.size} source object(s).", objects:)
    rescue StandardError => e
      failure("Error: #{sanitize_error(e.message)}")
    end

    def validate_query(query)
      return failure(connector_error) if connector_error

      sanitized_query = sanitize_query(query)
      return failure("No SQL query entered.") if sanitized_query.blank?

      columns = with_connection do |conn|
        conn.exec("BEGIN TRANSACTION READ ONLY")
        result = conn.exec("SELECT * FROM (#{sanitized_query}) _q LIMIT 0")
        conn.exec("ROLLBACK")
        result.fields
      end

      success(message: "Query is valid! Found #{columns.length} column(s).", columns:)
    rescue StandardError => e
      failure("Error: #{sanitize_error(e.message)}")
    end

    def sanitize_query(query)
      query.to_s.strip.sub(/;\s*\z/, "")
    end

    private

    def normalize_columns(columns)
      Array(columns).map do |column|
        {
          "name" => column["name"] || column[:name],
          "type" => column["type"] || column[:type],
          "nullable" => column["nullable"] == true || column[:nullable] == true,
        }.compact
      end
    end

    def connector_error
      return "No connector selected." if @connector.nil?
      return "Connector must be a SQL Database." unless @connector.connector_type == "sql_database"
      return "Only PostgreSQL is supported." unless @connector.adapter_type == "postgresql"

      nil
    end

    def success(message:, objects: [], columns: [])
      Result.new(success?: true, message:, objects:, columns:)
    end

    def failure(message)
      Result.new(success?: false, message:, objects: [], columns: [])
    end

    def with_connection
      conn = connect_pg(build_pg_config_for(@connector))
      yield conn
    ensure
      begin
        conn&.exec("ROLLBACK")
      rescue StandardError
        nil
      end
      conn&.close
    end
  end
end
