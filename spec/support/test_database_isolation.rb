# frozen_string_literal: true

module TestDatabaseIsolation
  module_function

  IGNORED_TABLES = ["ar_internal_metadata", "schema_migrations"].freeze

  def truncate_all!
    connection_pools.each do |pool|
      pool.with_connection do |connection|
        tables = cached_table_names(pool, connection)
        next if tables.empty?

        quoted_tables = tables.map { |table| connection.quote_table_name(table) }

        connection.disable_referential_integrity do
          connection.execute("TRUNCATE TABLE #{quoted_tables.join(", ")} RESTART IDENTITY CASCADE")
        end
      end
    end
  end

  def connection_pools
    ActiveRecord::Base.connection_handler.connection_pool_list(:all)
  end

  def cached_table_names(pool, connection)
    table_names_cache[pool.db_config.name] ||= connection.tables - IGNORED_TABLES
  end

  def table_names_cache
    @table_names_cache ||= {}
  end
end

RSpec.shared_context "with commit_db", :commit_db do
  self.use_transactional_tests = false
end

RSpec.shared_context "with js system", :js, type: :system do
  self.use_transactional_tests = false
end
