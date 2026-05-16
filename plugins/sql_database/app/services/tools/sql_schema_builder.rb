# frozen_string_literal: true

module Tools
  # Builds a compact textual schema description from the discovered schema
  # stored in a SqlDatabase connector. This text is included in the LLM prompt
  # so the model understands the available tables, columns, and relationships.
  #
  # Works with the JSONB `discovered_schema` and `selected_objects` fields
  # already populated by SchemaDiscoverer.
  #
  # Usage:
  #   schema_text = Tools::SqlSchemaBuilder.call(sql_database)
  #
  class SqlSchemaBuilder
    SEPARATOR = "=" * 60

    def self.call(sql_database, sql_query: nil)
      new(sql_database, sql_query:).call
    end

    def initialize(sql_database, sql_query: nil)
      @sql_database = sql_database
      @sql_query = sql_query
    end

    def call
      objects = selected_objects
      return "No schema information available." if objects.empty?

      parts = []
      parts << "SCHEMA"
      parts << SEPARATOR

      objects.each { |obj| parts << object_block(obj) }

      parts << ""
      parts << "RELATIONSHIPS"
      parts << ("-" * 40)
      parts << build_relationships(objects)

      parts.join("\n")
    end

    private

    def selected_objects
      all_objects = discovered_objects
      return all_objects if all_objects.empty?

      selected_names = fetch_selected_names
      return all_objects if selected_names.empty?

      all_objects.select { |obj| selected_names.include?(obj["name"]) }
    end

    def schema_source
      @sql_query || @sql_database
    end

    def discovered_objects
      schema = schema_source.try(:discovered_schema) || {}
      schema.is_a?(Hash) ? (schema["objects"] || []) : []
    end

    def fetch_selected_names
      schema_source.try(:selected_object_names) || []
    end

    def object_block(obj)
      lines = []
      lines << ""
      lines << "#{obj["name"]} (#{obj["type"]})"

      columns = obj["columns"] || []
      if columns.any?
        lines << "  Columns:"
        columns.each do |col|
          col_line = "    #{col["name"]} : #{col["type"]}"
          col_line += " NOT NULL" unless col["nullable"]
          col_line += " DEFAULT #{col["default"]}" if col["default"].present?
          lines << col_line
        end
      end

      lines.join("\n")
    end

    # Infer relationships from column naming conventions (*_id columns).
    def build_relationships(objects)
      object_names = objects.to_set { |o| o["name"] }
      edges = objects.flat_map { |obj| edges_for_object(obj, object_names) }

      return "No relationships detected." if edges.empty?

      edges.uniq.sort.join("\n")
    end

    def edges_for_object(obj, object_names)
      fk_columns = (obj["columns"] || []).select { |col| col["name"].end_with?("_id") }

      fk_columns.flat_map do |col|
        ref_base = col["name"].sub(/_id$/, "")
        matching_targets(object_names, ref_base).map do |target|
          "#{obj["name"]}.#{col["name"]} -> #{target}.id"
        end
      end
    end

    def matching_targets(object_names, ref_base)
      object_names.select do |name|
        name == ref_base || name == "#{ref_base}s" || name.end_with?("_#{ref_base}s")
      end
    end
  end
end
