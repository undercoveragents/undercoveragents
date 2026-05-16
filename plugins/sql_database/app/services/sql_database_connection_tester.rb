# frozen_string_literal: true

# Connection tester for SQL Database connectors.
class SqlDatabaseConnectionTester < BaseConnectionTester
  CONNECT_TIMEOUT = 10
  POSTGRESQL_DATABASES_QUERY = "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname"
  MYSQL_DATABASES_QUERY = "SHOW DATABASES"

  def call
    adapter = @params[:adapter_type] || "postgresql"

    connection_config = build_connection_config(adapter)
    test_connection(connection_config)
  rescue StandardError => e
    failure(sanitize_error(e.message))
  end

  def available_databases
    adapter = @params[:adapter_type] || "postgresql"

    connection_config = build_connection_config(adapter, for_database_listing: true)
    fetch_available_databases(adapter, connection_config)
  rescue StandardError => e
    failure(sanitize_error(e.message))
  end

  private

  def build_connection_config(adapter, for_database_listing: false)
    if @params[:connection_string].present?
      return { url: @params[:connection_string], connect_timeout: CONNECT_TIMEOUT }
    end

    config = {
      host: @params[:host],
      port: effective_port(adapter),
      database: database_name_for(adapter, for_database_listing:),
      username: @params[:username],
      password: @params[:encrypted_password],
      connect_timeout: CONNECT_TIMEOUT,
    }

    config[:sslmode] = "require" if @params[:ssl_enabled].to_s == "1" || @params[:ssl_enabled] == true
    config.compact
  end

  def effective_port(adapter)
    return @params[:port].to_i if @params[:port].present?

    Connectors::SqlDatabase::DEFAULT_PORTS[adapter]
  end

  def database_name_for(adapter, for_database_listing: false)
    return @params[:database_name] unless for_database_listing

    case adapter
    when "postgresql"
      @params[:database_name].presence || "postgres"
    when "mysql"
      nil
    else
      @params[:database_name]
    end
  end

  def test_connection(config)
    adapter = @params[:adapter_type] || "postgresql"

    case adapter
    when "postgresql"
      test_postgresql(config)
    when "mysql"
      test_mysql(config)
    when "sqlite"
      test_sqlite(config)
    else
      failure("Adapter '#{adapter}' is not yet supported for connection testing.")
    end
  end

  def fetch_available_databases(adapter, config)
    case adapter
    when "postgresql"
      fetch_postgresql_databases(config)
    when "mysql"
      fetch_mysql_databases(config)
    when "sqlite"
      failure("Database discovery is not available for SQLite. Enter the database file path manually.")
    else
      failure("Adapter '#{adapter}' is not yet supported for database discovery.")
    end
  end

  def test_postgresql(config)
    require "pg"

    conn = postgresql_connection(config)

    result = conn.exec("SELECT version()")
    version = result.first["version"]
    conn.close

    success("Connected successfully", version:)
  end

  def fetch_postgresql_databases(config)
    require "pg"

    conn = postgresql_connection(config)

    databases = conn.exec(POSTGRESQL_DATABASES_QUERY).column_values(0)
    conn.close

    success("Loaded #{databases.size} databases", databases:)
  end

  def test_mysql(config)
    require "mysql2"

    client = mysql_client(config, include_database: true)

    result = client.query("SELECT VERSION() AS version")
    version = result.first["version"]
    client.close

    success("Connected successfully", version:)
  end

  def fetch_mysql_databases(config)
    require "mysql2"

    client = mysql_client(config, include_database: false)

    databases = client.query(MYSQL_DATABASES_QUERY).map { |row| row.values.first }
    client.close

    success("Loaded #{databases.size} databases", databases:)
  end

  def test_sqlite(config)
    require "sqlite3"

    db_path = config[:database]
    raise SQLite3::Exception, "Database file not found: #{db_path}" unless File.exist?(db_path.to_s)

    db = SQLite3::Database.new(db_path)
    version = db.get_first_value("SELECT sqlite_version()")
    db.close

    success("Connected successfully", version: "SQLite #{version}")
  end

  def postgresql_connection(config)
    return PG.connect(config[:url]) if config[:url]

    PG.connect(**postgresql_connection_config(config))
  end

  def postgresql_connection_config(config)
    {
      host: config[:host],
      port: config[:port],
      dbname: config[:database],
      user: config[:username],
      password: config[:password],
      connect_timeout: config[:connect_timeout],
      sslmode: config[:sslmode],
    }.compact
  end

  def mysql_client(config, include_database:)
    client_config = mysql_connection_config(config, include_database:)
    Mysql2::Client.new(config[:url] || client_config)
  end

  def mysql_connection_config(config, include_database:)
    {
      host: config[:host],
      port: config[:port],
      database: include_database ? config[:database] : nil,
      username: config[:username],
      password: config[:password],
      connect_timeout: config[:connect_timeout],
      ssl_mode: config[:sslmode] == "require" ? :required : :disabled,
    }.compact
  end
end
