# frozen_string_literal: true

module Tools
  class SqlToolInstructionsBuilder
    MAX_LISTED_OBJECTS = 8
    MAX_INSTRUCTION_LENGTH = 500

    def self.call(sql_query)
      new(sql_query).call
    end

    def initialize(sql_query)
      @sql_query = sql_query
    end

    def call
      return SqlQueryTool::DEFAULT_TOOL_PROMPT if visible_objects.empty?

      [
        "Use this read-only #{adapter_label} database tool to answer questions about #{object_summary}.",
        "Use exact table and column names from the provided schema context.",
        ("Join related records through detected *_id relationships when needed." if relationship_hint?),
      ].compact.join(" ").truncate(MAX_INSTRUCTION_LENGTH)
    end

    private

    def adapter_label
      @sql_query.connector&.adapter_type.to_s.titleize.presence || "SQL"
    end

    def visible_objects
      @visible_objects ||= begin
        objects = discovered_objects
        names = @sql_query.selected_object_names
        names.empty? ? objects : objects.select { |object| names.include?(object["name"]) }
      end
    end

    def discovered_objects
      schema = @sql_query.discovered_schema
      return [] unless schema.is_a?(Hash)

      Array(schema["objects"])
    end

    def object_summary
      names = visible_objects.pluck("name")
      listed_names = names.first(MAX_LISTED_OBJECTS)
      remaining_count = names.length - listed_names.length

      summary = listed_names.join(", ")
      summary = "#{summary}, plus #{remaining_count} more" if remaining_count.positive?
      "the visible schema (#{summary})"
    end

    def relationship_hint?
      visible_objects.any? do |object|
        Array(object["columns"]).any? { |column| column["name"].to_s.end_with?("_id") }
      end
    end
  end
end
