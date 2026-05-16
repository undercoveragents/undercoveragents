# frozen_string_literal: true

module SqlConnectionConfigBuilder
  CONNECT_TIMEOUT = 10
  FALLBACK_CONNECT_ERRORS = [ArgumentError, PG::Error].freeze

  private

  def build_pg_config_for(sql_database)
    config = {
      host: sql_database.host,
      port: sql_database.effective_port,
      dbname: sql_database.database_name,
      user: sql_database.username,
      password: sql_database.encrypted_password,
      connect_timeout: CONNECT_TIMEOUT,
    }
    config[:url] = sql_database.connection_string if sql_database.connection_string?
    config[:sslmode] = "require" if sql_database.ssl_enabled?
    config.compact
  end

  def connect_pg(config)
    return PG.connect(**config.except(:url)) unless config[:url]

    PG.connect(config[:url])
  rescue *FALLBACK_CONNECT_ERRORS => e
    fallback_config = config.except(:url).compact
    raise e if fallback_config.empty? || !string_not_matched_error?(e)

    PG.connect(**fallback_config)
  end

  def string_not_matched_error?(error)
    error.message.to_s.downcase.include?("string not matched")
  end
end
