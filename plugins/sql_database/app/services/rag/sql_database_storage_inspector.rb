# frozen_string_literal: true

module Rag
  class SqlDatabaseStorageInspector
    Result = Data.define(:success?, :message, :objects, :document_columns, :chunk_columns, :issues)

    def initialize(connector)
      @connector = connector
    end

    def schema_options
      return failure(connector_error) if connector_error

      discovery = Tools::SchemaDiscoverer.new(@connector).call
      return failure(discovery.message) unless discovery.success?

      objects = Array(discovery.schema&.dig("objects"))
                .select { |object| object["type"] == "table" }
                .map { |object| normalize_object(object) }

      success(message: "Loaded #{objects.size} storage table(s).", objects:)
    rescue StandardError => e
      failure("Error: #{e.message}")
    end

    def validate_existing_tables(selection)
      options = schema_options
      return options unless options.success?

      normalized_selection = normalize_selection(selection)
      documents, chunks = selected_tables(options.objects, normalized_selection)
      issues = document_issues(documents, normalized_selection[:metadata_field_mappings])
      issues.concat(chunk_issues(chunks, normalized_selection))

      return validation_success(options.objects, documents, chunks, normalized_selection) if issues.empty?

      validation_failure(options.objects, documents, chunks, issues)
    end

    private

    def normalize_selection(selection)
      {
        documents_table: selection[:documents_table],
        chunks_table: selection[:chunks_table],
        content_field: selection[:content_field],
        embedding_field: selection[:embedding_field],
        document_reference_field: selection[:document_reference_field],
        metadata_field_mappings: selection[:metadata_field_mappings] || {},
      }
    end

    def selected_tables(objects, selection)
      documents = objects.find { |object| object["name"] == selection[:documents_table] }
      chunks = objects.find { |object| object["name"] == selection[:chunks_table] }
      [documents, chunks]
    end

    def document_issues(documents, metadata_field_mappings)
      issues = []
      validate_documents_table(documents, metadata_field_mappings, issues)
      issues
    end

    def chunk_issues(chunks, selection)
      issues = []
      validate_chunks_table(
        chunks,
        selection[:content_field],
        selection[:embedding_field],
        selection[:document_reference_field],
        issues,
      )
      issues
    end

    def validation_success(objects, documents, chunks, selection)
      success(
        message: success_message(selection[:documents_table], selection[:chunks_table]),
        objects:,
        document_columns: column_names(documents),
        chunk_columns: column_names(chunks),
      )
    end

    def validation_failure(objects, documents, chunks, issues)
      failure(
        issues.pluck(:message).join("; "),
        objects:,
        document_columns: column_names(documents),
        chunk_columns: column_names(chunks),
        issues:,
      )
    end

    def validate_documents_table(documents, metadata_field_mappings, issues)
      unless documents
        issues << issue(:documents_table, "must match an existing table")
        return
      end

      columns = column_names(documents)
      issues << issue(:documents_table, "must include an 'id' column") unless columns.include?("id")
      issues << issue(:documents_table, "must include a 'content_hash' column") unless columns.include?("content_hash")

      metadata_field_mappings.each_value do |column_name|
        next if columns.include?(column_name.to_s)

        issues << issue(:documents_table, "must include metadata column '#{column_name}'")
      end
    end

    def validate_chunks_table(chunks, content_field, embedding_field, document_reference_field, issues)
      unless chunks
        issues << issue(:chunks_table, "must match an existing table")
        return
      end

      columns = column_names(chunks)
      append_missing_chunk_column_issue(issues, :content_field, content_field, columns)
      append_missing_chunk_column_issue(issues, :embedding_field, embedding_field, columns)
      append_missing_chunk_column_issue(issues, :document_reference_field, document_reference_field, columns)
    end

    def append_missing_chunk_column_issue(issues, field, column_name, columns)
      return unless missing_column?(column_name, columns)

      issues << issue(field, "was not found in the selected chunks table")
    end

    def column_names(object)
      Array(object&.dig("columns")).pluck("name")
    end

    def missing_column?(column_name, columns)
      column_name.present? && columns.exclude?(column_name)
    end

    def success_message(documents_table, chunks_table)
      "Existing storage schema is ready: #{documents_table} + #{chunks_table}."
    end

    def normalize_object(object)
      {
        "name" => object["name"],
        "type" => object["type"],
        "columns" => Array(object["columns"]).map do |column|
          {
            "name" => column["name"] || column[:name],
            "type" => column["type"] || column[:type],
            "nullable" => column["nullable"] == true || column[:nullable] == true,
          }.compact
        end,
      }
    end

    def connector_error
      return "No connector selected." if @connector.nil?
      return "Connector must be a SQL Database." unless @connector.connector_type == "sql_database"
      return "Only PostgreSQL is supported." unless @connector.adapter_type == "postgresql"

      nil
    end

    def success(message:, objects:, document_columns: [], chunk_columns: [], issues: [])
      Result.new(success?: true, message:, objects:, document_columns:, chunk_columns:, issues:)
    end

    def failure(message, objects: [], document_columns: [], chunk_columns: [], issues: [])
      Result.new(success?: false, message:, objects:, document_columns:, chunk_columns:, issues:)
    end

    def issue(field, message)
      { field:, message: }
    end
  end
end
