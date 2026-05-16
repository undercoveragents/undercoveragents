# frozen_string_literal: true

module Rag
  class SqlDatabaseSourceExecutor
    include SqlConnectionConfigBuilder
    include SqlErrorSanitizer

    def initialize(step_config, context = {})
      @config = step_config
      @context = context
    end

    def call(_documents = [])
      all_docs = []
      each_batch { |batch| all_docs.concat(batch) }
      all_docs
    end

    def each_batch(&)
      sql_database = @config.connector
      validate_adapter!(sql_database)

      config = build_pg_config_for(sql_database)
      conn = connect_pg(config)

      begin
        conn.exec("BEGIN TRANSACTION READ ONLY")
        conn.exec("DECLARE ing_cursor CURSOR FOR #{@config.query}")
        fetch_from_cursor(conn, &)
        conn.exec("ROLLBACK")
      ensure
        conn.close
      end
    end

    private

    def fetch_from_cursor(conn)
      doc_index = 0
      loop do
        result = conn.exec("FETCH #{@config.batch_size} FROM ing_cursor")
        rows = result.to_a
        break if rows.empty?

        documents = rows.map { |row| build_document(row, (doc_index += 1) - 1) }
        yield documents
      end
      conn.exec("CLOSE ing_cursor")
    end

    def validate_adapter!(sql_database)
      return if sql_database.adapter_type == "postgresql"

      raise "Only PostgreSQL adapters are supported for rag sources"
    end

    def build_document(row, index)
      content = row[@config.content_column].to_s
      metadata = extract_metadata(row)

      Rag::Document.new(
        id: "doc_#{index}",
        content:,
        metadata:,
      )
    end

    def extract_metadata(row)
      columns = @config.metadata_columns
      return {} unless columns.is_a?(Array)

      columns.each_with_object({}) do |col, meta|
        col_name = col.is_a?(Hash) ? (col["name"] || col[:name]) : col.to_s
        meta[col_name] = row[col_name] if col_name.present? && row.key?(col_name)
      end
    end
  end
end
