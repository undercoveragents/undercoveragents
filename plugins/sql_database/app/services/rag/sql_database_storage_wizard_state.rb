# frozen_string_literal: true

module Rag
  class SqlDatabaseStorageWizardState
    Status = Data.define(:kind, :message)

    def initialize(steppable)
      @steppable = steppable
    end

    def storage_mode
      steppable.storage_mode.to_s.presence || inferred_storage_mode
    end

    def existing_mode?
      storage_mode == "existing"
    end

    def table_options
      schema_objects.map { |object| [table_label(object), object["name"]] }
    end

    def chunk_field_options
      Array(selected_chunks_table&.fetch("columns", [])).map do |column|
        [column_label(column), column["name"]]
      end
    end

    def status
      return missing_connector_status if steppable.connector.blank?
      return new_mode_status unless existing_mode?

      existing_mode_status
    end

    private

    attr_reader :steppable

    def existing_mode_status
      return schema_failure_status unless schema_result.success?
      return missing_tables_status if missing_table_selection?
      return duplicate_tables_status if duplicate_tables?
      return missing_fields_status if missing_field_selection?
      return Status.new(kind: "error", message: validation_result.message) unless validation_result.success?

      Status.new(kind: "success", message: validation_result.message)
    end

    def inferred_storage_mode
      steppable.auto_create_tables? ? "new" : "existing"
    end

    def missing_table_selection?
      steppable.documents_table.blank? || steppable.chunks_table.blank?
    end

    def duplicate_tables?
      steppable.documents_table.present? && steppable.documents_table == steppable.chunks_table
    end

    def missing_field_selection?
      [steppable.content_field, steppable.embedding_field, steppable.document_reference_field].any?(&:blank?)
    end

    def selected_chunks_table
      @selected_chunks_table ||= schema_objects.find { |object| object["name"] == steppable.chunks_table }
    end

    def schema_objects
      @schema_objects ||= schema_result.success? ? Array(schema_result.objects) : []
    end

    def schema_result
      @schema_result ||= Rag::SqlDatabaseStorageInspector.new(steppable.connector).schema_options
    end

    def validation_result
      @validation_result ||= Rag::SqlDatabaseStorageInspector.new(steppable.connector).validate_existing_tables(
        documents_table: steppable.documents_table,
        chunks_table: steppable.chunks_table,
        content_field: steppable.content_field,
        embedding_field: steppable.embedding_field,
        document_reference_field: steppable.document_reference_field,
        metadata_field_mappings: steppable.metadata_field_mappings,
      )
    end

    def column_names(object)
      Array(object["columns"]).pluck("name")
    end

    def column_label(column)
      type = column["type"].to_s.presence
      return column["name"].to_s if type.blank?

      %(#{column["name"]} - #{type})
    end

    def table_label(object)
      %(#{object["name"]} - #{column_names(object).size} columns)
    end

    def missing_connector_status
      Status.new(
        kind: "info",
        message: "Choose a PostgreSQL connector to inspect storage tables or define a new schema.",
      )
    end

    def new_mode_status
      Status.new(
        kind: "info",
        message: "New mode creates the configured documents and chunks tables on first run if needed. " \
                 "It also ensures the documents table has content_hash and configured metadata columns.",
      )
    end

    def schema_failure_status
      Status.new(kind: "error", message: schema_result.message)
    end

    def missing_tables_status
      Status.new(
        kind: "info",
        message: "Choose both the documents table and the chunks table to inspect the available columns.",
      )
    end

    def duplicate_tables_status
      Status.new(kind: "error", message: "Documents and chunks tables must be different.")
    end

    def missing_fields_status
      Status.new(
        kind: "info",
        message: "Choose the content, embedding, and document reference columns to validate the existing schema.",
      )
    end
  end
end
