# frozen_string_literal: true

module Rag
  module SqlDatabaseStorageSchemaManagement
    private

    def ensure_tables_exist(conn, documents)
      all_types = effective_metadata_column_types(documents)
      create_documents_table(conn, all_types)
      add_missing_metadata_columns(conn, all_types)
      ensure_content_hash_column(conn)
      create_chunks_table(conn)
    end

    def create_documents_table(conn, all_types)
      metadata_col_sql = build_metadata_columns_sql(all_types)
      metadata_part = metadata_col_sql.empty? ? "" : ",\n  #{metadata_col_sql}"

      sql = <<~SQL.squish
        CREATE TABLE IF NOT EXISTS #{qi(@config.documents_table)} (
          id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
          content_hash varchar(64),
          created_at timestamptz NOT NULL DEFAULT now()#{metadata_part}
        )
      SQL
      conn.exec(sql)
    end

    def effective_metadata_column_types(documents)
      explicit = @config.metadata_column_types.presence || {}
      auto_keys = documents.flat_map { |d| d.metadata.keys.map(&:to_s) }.uniq
      auto_keys.select { |k| valid_identifier?(k) }.each_with_object(explicit.dup) do |key, types|
        types[key] ||= "text"
      end
    end

    def add_missing_metadata_columns(conn, types)
      types.each do |column, sql_type|
        safe_type = safe_sql_type(sql_type.to_s)
        conn.exec(
          "ALTER TABLE #{qi(@config.documents_table)} " \
          "ADD COLUMN IF NOT EXISTS #{qi(column)} #{safe_type}",
        )
      end
    end

    def build_metadata_columns_sql(types)
      types.map do |column, sql_type|
        "#{qi(column)} #{safe_sql_type(sql_type.to_s)}"
      end.join(",\n  ")
    end

    def create_chunks_table(conn)
      dim = @config.embedding_dimensions.to_i
      raise "Invalid embedding_dimensions: #{dim}" unless dim.positive?

      sql = <<~SQL.squish
        CREATE TABLE IF NOT EXISTS #{qi(@config.chunks_table)} (
          id bigserial PRIMARY KEY,
          #{qi(@config.document_reference_field)} uuid NOT NULL
            REFERENCES #{qi(@config.documents_table)}(id) ON DELETE CASCADE,
          #{qi(@config.content_field)} text NOT NULL,
          #{qi(@config.embedding_field)} vector(#{dim}),
          created_at timestamptz NOT NULL DEFAULT now()
        )
      SQL
      conn.exec(sql)
    end

    def safe_sql_type(type)
      normalized = type.downcase
      allowed = RagSteps::SqlDatabaseStorage::ALLOWED_COLUMN_TYPES
      raise "Unsupported SQL type: #{type}" unless allowed.include?(normalized)

      normalized
    end

    def ensure_content_hash_column(conn)
      conn.exec(
        "ALTER TABLE #{qi(@config.documents_table)} " \
        "ADD COLUMN IF NOT EXISTS content_hash varchar(64)",
      )
    rescue PG::Error
      nil
    end
  end
end
