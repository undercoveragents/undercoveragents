# frozen_string_literal: true

module Tools
  module Discoverers
    class Sqlite
      def initialize(sql_database)
        @sql_database = sql_database
      end

      def discover
        require "sqlite3"

        db_path = @sql_database.database_name
        raise SQLite3::Exception, "Database file not found: #{db_path}" unless File.exist?(db_path.to_s)

        db = SQLite3::Database.new(db_path)
        db.results_as_hash = true
        objects = [*query_objects(db, "table"), *query_objects(db, "view")]
        db.close
        objects
      end

      private

      def query_objects(db, type)
        extra = type == "table" ? " AND name NOT LIKE 'sqlite_%'" : ""
        rows = db.execute("SELECT name FROM sqlite_master WHERE type='#{type}'#{extra} ORDER BY name")
        rows.map do |row|
          { "type" => type, "name" => row["name"], "columns" => discover_columns(db, row["name"]) }
        end
      end

      def discover_columns(db, table_name)
        columns = db.execute("PRAGMA table_info('#{table_name.gsub("'", "''")}')")
        columns.map do |col|
          { "name" => col["name"], "type" => col["type"], "nullable" => col["notnull"].zero? }
        end
      end
    end
  end
end
