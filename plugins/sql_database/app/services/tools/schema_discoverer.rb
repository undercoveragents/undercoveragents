# frozen_string_literal: true

module Tools
  class SchemaDiscoverer
    include ConnectionConfigBuilder

    Result = Data.define(:success?, :schema, :message)

    def initialize(sql_database)
      @sql_database = sql_database
    end

    def call
      case @sql_database.adapter_type
      when "postgresql" then discover_postgresql
      when "mysql"      then success(Discoverers::Mysql.new(@sql_database).discover)
      when "sqlite"     then success(Discoverers::Sqlite.new(@sql_database).discover)
      else failure("Schema discovery not supported for adapter '#{@sql_database.adapter_type}'.")
      end
    rescue StandardError => e
      failure("Discovery failed: #{sanitize_error(e.message)}")
    end

    private

    def discover_postgresql
      require "pg"

      conn = connect_pg(build_pg_config_for(@sql_database))
      schema_name = @sql_database.schema_name || "public"
      objects = discover_pg_objects(conn, schema_name)
      conn.close
      success(objects)
    end

    def discover_pg_objects(conn, schema_name)
      [
        *discover_pg_tables(conn, schema_name),
        *discover_pg_views(conn, schema_name),
        *discover_pg_matviews(conn, schema_name),
      ]
    end

    def discover_pg_tables(conn, schema_name)
      rows = conn.exec_params(<<~SQL.squish, [schema_name])
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = $1 AND table_type = 'BASE TABLE' ORDER BY table_name
      SQL

      rows.map do |row|
        columns = discover_pg_columns(conn, schema_name, row["table_name"])
        { "type" => "table", "name" => row["table_name"], "columns" => columns }
      end
    end

    def discover_pg_views(conn, schema_name)
      rows = conn.exec_params(<<~SQL.squish, [schema_name])
        SELECT table_name FROM information_schema.views
        WHERE table_schema = $1 ORDER BY table_name
      SQL

      rows.map do |row|
        columns = discover_pg_columns(conn, schema_name, row["table_name"])
        { "type" => "view", "name" => row["table_name"], "columns" => columns }
      end
    end

    def discover_pg_matviews(conn, schema_name)
      rows = conn.exec_params(<<~SQL.squish, [schema_name])
        SELECT matviewname AS name FROM pg_matviews
        WHERE schemaname = $1 ORDER BY matviewname
      SQL

      rows.map do |row|
        columns = discover_pg_matview_columns(conn, schema_name, row["name"])
        { "type" => "materialized_view", "name" => row["name"], "columns" => columns }
      end
    end

    def discover_pg_columns(conn, schema_name, table_name)
      result = conn.exec_params(<<~SQL.squish, [schema_name, table_name])
        SELECT column_name, data_type, is_nullable, column_default
        FROM information_schema.columns
        WHERE table_schema = $1 AND table_name = $2 ORDER BY ordinal_position
      SQL

      result.map do |col|
        { "name" => col["column_name"], "type" => col["data_type"],
          "nullable" => col["is_nullable"] == "YES", "default" => col["column_default"], }
      end
    end

    def discover_pg_matview_columns(conn, schema_name, matview_name)
      result = conn.exec_params(<<~SQL.squish, [schema_name, matview_name])
        SELECT a.attname AS column_name,
               pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
               NOT a.attnotnull AS nullable
        FROM pg_attribute a JOIN pg_class c ON a.attrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = $1 AND c.relname = $2 AND a.attnum > 0 AND NOT a.attisdropped
        ORDER BY a.attnum
      SQL

      result.map do |col|
        { "name" => col["column_name"], "type" => col["data_type"], "nullable" => col["nullable"] == "t" }
      end
    end

    def success(objects)
      Result.new(success?: true, schema: { "objects" => objects }, message: "Discovered #{objects.size} objects")
    end

    def failure(message)
      Result.new(success?: false, schema: nil, message:)
    end
  end
end
