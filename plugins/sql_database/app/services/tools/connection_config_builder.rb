# frozen_string_literal: true

module Tools
  module ConnectionConfigBuilder
    include SqlErrorSanitizer

    CONNECT_TIMEOUT = 10

    private

    def build_pg_config_for(sql_database)
      return { url: sql_database.connection_string } if sql_database.connection_string?

      config = {
        host: sql_database.host,
        port: sql_database.effective_port,
        dbname: sql_database.database_name,
        user: sql_database.username,
        password: sql_database.encrypted_password,
        connect_timeout: CONNECT_TIMEOUT,
      }
      config[:sslmode] = "require" if sql_database.ssl_enabled?
      config.compact
    end

    def build_mysql_config_for(sql_database)
      return { url: sql_database.connection_string } if sql_database.connection_string?

      {
        host: sql_database.host,
        port: sql_database.effective_port,
        database: sql_database.database_name,
        username: sql_database.username,
        password: sql_database.encrypted_password,
        connect_timeout: CONNECT_TIMEOUT,
      }.compact
    end

    def connect_pg(config)
      config[:url] ? PG.connect(config[:url]) : PG.connect(**config.except(:url))
    end

    def connect_mysql_client(config)
      Mysql2::Client.new(**config)
    end
  end
end
