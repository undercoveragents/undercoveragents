# frozen_string_literal: true

module Tools
  module Discoverers
    class Mysql
      include ConnectionConfigBuilder

      def initialize(sql_database)
        @sql_database = sql_database
      end

      def discover
        require "mysql2"

        client = connect_mysql_client(build_mysql_config_for(@sql_database))
        objects = discover_objects(client)
        client.close
        objects
      end

      private

      def discover_objects(client)
        db = @sql_database.database_name
        [
          *query_objects(client, db, "BASE TABLE", "table"),
          *query_objects(client, db, nil, "view"),
        ]
      end

      def query_objects(client, db, table_type, object_type)
        source = table_type ? "information_schema.tables" : "information_schema.views"
        where = "table_schema = '#{client.escape(db)}'"
        where += " AND table_type = '#{table_type}'" if table_type

        rows = client.query("SELECT table_name FROM #{source} WHERE #{where} ORDER BY table_name")
        rows.map do |row|
          name = row["table_name"] || row["TABLE_NAME"]
          { "type" => object_type, "name" => name, "columns" => discover_columns(client, db, name) }
        end
      end

      def discover_columns(client, database_name, table_name)
        result = client.query(
          "SELECT column_name, data_type, is_nullable, column_default " \
          "FROM information_schema.columns " \
          "WHERE table_schema = '#{client.escape(database_name)}' " \
          "AND table_name = '#{client.escape(table_name)}' ORDER BY ordinal_position",
        )

        result.map do |col|
          { "name" => col["column_name"] || col["COLUMN_NAME"], "type" => col["data_type"] || col["DATA_TYPE"],
            "nullable" => (col["is_nullable"] || col["IS_NULLABLE"]) == "YES",
            "default" => col["column_default"] || col["COLUMN_DEFAULT"], }
        end
      end
    end
  end
end
