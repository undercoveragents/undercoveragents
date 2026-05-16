# frozen_string_literal: true

module Tools
  # Executes SQL queries safely against an external database connection.
  # Supports PostgreSQL, MySQL, and SQLite with read-only transaction guards.
  #
  # Mixed into SqlQueryService — separated for clarity and class-length compliance.
  module SqlQueryExecutor
    include ConnectionConfigBuilder

    private

    def with_connection(&)
      case @sql_database.adapter_type
      when "postgresql" then with_pg_connection(&)
      when "mysql" then with_mysql_connection(&)
      when "sqlite" then with_sqlite_connection(&)
      else
        raise "Unsupported adapter: #{@sql_database.adapter_type}"
      end
    end

    def with_pg_connection
      require "pg"
      conn = connect_pg(build_pg_config_for(@sql_database))
      begin
        yield conn
      ensure
        conn.close
      end
    end

    def with_mysql_connection
      require "mysql2"
      conn = connect_mysql_client(build_mysql_config_for(@sql_database))
      begin
        yield conn
      ensure
        conn.close
      end
    end

    def with_sqlite_connection
      require "sqlite3"
      conn = SQLite3::Database.new(@sql_database.database_name)
      conn.results_as_hash = true
      begin
        yield conn
      ensure
        conn.close
      end
    end

    def execute_sql(sql)
      validate_sql!(sql)

      with_connection do |conn|
        send("execute_#{@sql_database.adapter_type.sub("postgresql", "pg")}", conn, sql)
      end
    end

    def execute_pg(conn, sql)
      conn.exec("BEGIN")
      conn.exec("SET TRANSACTION READ ONLY")
      result = conn.exec(sql)
      rows = result.to_a
      conn.exec("ROLLBACK")
      rows
    rescue StandardError => e
      rollback_transaction(conn)
      raise e
    end

    def rollback_transaction(conn)
      conn.exec("ROLLBACK")
    rescue StandardError
      nil
    end

    def execute_mysql(conn, sql)
      conn.query("SET TRANSACTION READ ONLY")
      conn.query("START TRANSACTION")
      result = conn.query(sql, as: :hash)
      rows = result.to_a
      conn.query("ROLLBACK")
      rows
    end

    def execute_sqlite(conn, sql)
      conn.readonly = true
      conn.execute(sql)
    end
  end
end
