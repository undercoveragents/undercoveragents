# frozen_string_literal: true

module Rag
  class SqlDatabaseStorageExecutor
    include SqlConnectionConfigBuilder
    include SqlErrorSanitizer
    include SqlDatabaseStorageSchemaManagement

    IDENTIFIER_REGEX = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/
    UUID_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    def initialize(step_config, context = {})
      @config = step_config
      @context = context
    end

    def call(documents)
      sql_database = resolve_connector
      config = build_pg_config_for(sql_database)
      conn = connect_pg(config)

      begin
        conn.exec("BEGIN")
        ensure_tables_exist(conn, documents) if @config.auto_create_tables?
        execute_pre_load_action(conn)
        store_documents(conn, documents)
        conn.exec("COMMIT")
      rescue StandardError => e
        rollback_transaction(conn)
        raise e
      ensure
        conn.close
      end

      documents
    end

    def fetch_existing_content_hashes(hashes)
      return Set.new if hashes.empty?

      sql_database = resolve_connector
      config = build_pg_config_for(sql_database)
      conn = connect_pg(config)

      begin
        placeholders = hashes.each_index.map { |i| "$#{i + 1}" }
        result = conn.exec_params(
          "SELECT content_hash FROM #{qi(@config.documents_table)} " \
          "WHERE content_hash IN (#{placeholders.join(", ")})",
          hashes,
        )
        result.to_set { |row| row["content_hash"] }
      rescue PG::UndefinedTable, PG::UndefinedColumn
        Set.new
      ensure
        conn.close
      end
    end

    private

    def execute_pre_load_action(conn)
      case @config.pre_load_action
      when "truncate"
        conn.exec("TRUNCATE TABLE #{qi(@config.chunks_table)}, #{qi(@config.documents_table)} CASCADE")
      when "delete_matching"
        conn.exec("DELETE FROM #{qi(@config.chunks_table)}")
        conn.exec("DELETE FROM #{qi(@config.documents_table)}")
      end
    end

    def resolve_connector
      @config.connector || raise("Connector is required")
    end

    def rollback_transaction(conn)
      conn.exec("ROLLBACK")
    rescue StandardError
      nil
    end

    def store_documents(conn, documents)
      documents.each do |doc|
        doc_id = if @config.upsert_enabled?
                   insert_or_update_document(conn, doc)
                 else
                   insert_document(conn, doc)
                 end
        insert_chunks(conn, doc, doc_id)
      end
    end

    def insert_or_update_document(conn, doc)
      columns, values = build_document_columns_and_values(doc)
      column_values = columns.zip(values).to_h
      content_hash = column_values["content_hash"]

      existing_id = find_existing_document_id(conn, content_hash)
      return insert_document(conn, doc) if existing_id.blank?

      update_document_metadata(conn, existing_id, column_values)
      existing_id
    end

    def insert_document(conn, doc)
      columns, values = build_document_columns_and_values(doc)

      sql = if columns.empty?
              "INSERT INTO #{qi(@config.documents_table)} DEFAULT VALUES RETURNING id"
            else
              placeholders = values.each_index.map { |i| "$#{i + 1}" }
              "INSERT INTO #{qi(@config.documents_table)} (#{columns.map { |c| qi(c) }.join(", ")}) " \
                "VALUES (#{placeholders.join(", ")}) RETURNING id"
            end

      result = columns.empty? ? conn.exec(sql) : conn.exec_params(sql, values)
      result.first["id"]
    end

    def build_document_columns_and_values(doc)
      columns = []
      values = []

      uuid = valid_uuid(doc.id)
      if uuid
        columns << "id"
        values << uuid
      end

      columns << "content_hash"
      values << doc.content_hash

      resolved_metadata_mappings(doc).each do |meta_key, db_column|
        next unless doc.metadata.key?(meta_key) || doc.metadata.key?(meta_key.to_sym)

        columns << db_column.to_s
        values << (doc.metadata[meta_key] || doc.metadata[meta_key.to_sym])
      end

      [columns, values]
    end

    def resolved_metadata_mappings(doc)
      explicit = @config.metadata_field_mappings.presence
      return explicit if explicit

      doc.metadata.keys
         .map(&:to_s)
         .select { |k| valid_identifier?(k) }
         .to_h { |k| [k, k] }
    end

    def insert_chunks(conn, doc, doc_id)
      delete_existing_chunks(conn, doc_id) if @config.upsert_enabled?

      doc.chunks.each do |chunk|
        insert_chunk(conn, doc_id, chunk)
      end
    end

    def delete_existing_chunks(conn, doc_id)
      conn.exec_params(
        "DELETE FROM #{qi(@config.chunks_table)} WHERE #{qi(@config.document_reference_field)} = $1",
        [doc_id],
      )
    end

    def insert_chunk(conn, doc_id, chunk)
      columns, values = chunk_columns_and_values(doc_id, chunk)
      placeholders = values.each_index.map { |i| "$#{i + 1}" }
      sql = "INSERT INTO #{qi(@config.chunks_table)} (#{columns.join(", ")}) " \
            "VALUES (#{placeholders.join(", ")})"

      conn.exec_params(sql, values)
    end

    def chunk_columns_and_values(doc_id, chunk)
      columns = [qi(@config.document_reference_field), qi(@config.content_field)]
      values = [doc_id, chunk.content]

      if chunk.embedding.present?
        columns << qi(@config.embedding_field)
        values << "[#{chunk.embedding.join(",")}]"
      end

      [columns, values]
    end

    def find_existing_document_id(conn, content_hash)
      result = conn.exec_params(
        "SELECT id FROM #{qi(@config.documents_table)} WHERE content_hash = $1 LIMIT 1",
        [content_hash],
      )
      result.first&.fetch("id", nil)
    end

    def update_document_metadata(conn, doc_id, column_values)
      updatable = column_values.except("id", "content_hash")
      return if updatable.empty?

      keys = updatable.keys
      set_clauses = keys.each_index.map { |index| "#{qi(keys[index])} = $#{index + 1}" }
      values = updatable.values + [doc_id]

      conn.exec_params(
        "UPDATE #{qi(@config.documents_table)} SET #{set_clauses.join(", ")} WHERE id = $#{updatable.size + 1}",
        values,
      )
    end

    def valid_uuid(value)
      return nil if value.blank?

      value.to_s.match?(UUID_REGEX) ? value.to_s : nil
    end

    def valid_identifier?(str)
      str.to_s.match?(IDENTIFIER_REGEX)
    end

    def qi(identifier)
      str = identifier.to_s
      raise "Invalid identifier: #{str}" unless valid_identifier?(str)

      "\"#{str}\""
    end
  end
end
