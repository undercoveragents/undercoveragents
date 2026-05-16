# frozen_string_literal: true

module Rag
  class SqlDatabaseSourceWizardState
    Status = Data.define(:kind, :message)

    def initialize(steppable)
      @steppable = steppable
    end

    def source_mode
      steppable.source_mode.to_s.presence || inferred_source_mode
    end

    def table_mode?
      source_mode == "table"
    end

    def object_options
      schema_objects.map { |object| [object_label(object), object["name"]] }
    end

    def column_options
      available_columns.map { |column| [column_label(column), column_name(column)] }
    end

    def selected_object_type
      selected_object&.dig("type").to_s.presence || steppable.selected_object_type
    end

    def query_value
      return steppable.generated_query.to_s if table_mode?

      steppable.query.to_s
    end

    def status
      return missing_connector_status if steppable.connector.blank?
      return table_status if table_mode?

      query_status
    end

    private

    attr_reader :steppable

    def inferred_source_mode
      return "table" if steppable.selected_object_name.present?
      return "query" if steppable.query.present?

      "table"
    end

    def table_status
      return Status.new(kind: "error", message: schema_result.message) unless schema_result.success?
      return missing_table_status unless selected_object

      Status.new(kind: "success", message: loaded_table_message)
    end

    def query_status
      return blank_query_status if query_value.blank?
      return Status.new(kind: "error", message: query_result.message) unless query_result.success?

      Status.new(kind: "success", message: query_result.message)
    end

    def selected_object
      @selected_object ||= schema_objects.find { |object| object["name"] == steppable.selected_object_name }
    end

    def available_columns
      @available_columns ||= if table_mode?
                               Array(selected_object&.fetch("columns", []))
                             else
                               Array(query_result.columns).map { |name| { "name" => name } }
                             end
    end

    def schema_objects
      @schema_objects ||= schema_result.success? ? Array(schema_result.objects) : []
    end

    def schema_result
      @schema_result ||= Rag::SqlDatabaseSourceInspector.new(steppable.connector).schema_options
    end

    def query_result
      @query_result ||= Rag::SqlDatabaseSourceInspector.new(steppable.connector).validate_query(query_value)
    end

    def object_label(object)
      %(#{object["name"]} - #{object["type"].to_s.tr("_", " ")})
    end

    def column_label(column)
      type = column["type"].to_s.presence
      return column_name(column) if type.blank?

      "#{column_name(column)} - #{type}"
    end

    def column_name(column)
      column["name"].to_s
    end

    def missing_connector_status
      Status.new(kind: "info", message: "Choose a PostgreSQL connector to begin.")
    end

    def missing_table_status
      Status.new(kind: "info", message: "Choose a table or view to load its available columns.")
    end

    def blank_query_status
      Status.new(
        kind: "info",
        message: "Write a read-only SELECT query, then analyze it to load its result columns.",
      )
    end

    def loaded_table_message
      "Loaded #{available_columns.size} columns from #{selected_object["name"]}."
    end
  end
end
