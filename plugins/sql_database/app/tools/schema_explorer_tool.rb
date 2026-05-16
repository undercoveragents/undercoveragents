# frozen_string_literal: true

# RubyLLM tool that executes read-only SQL queries against the target database for exploration.
#
# This is a simplified version of SqlQueryTool that executes raw SQL
# directly (no NL→SQL translation) since the agent itself writes SQL.
#
# Safety:
# - Only SELECT/WITH statements allowed
# - Executed inside a READ-ONLY transaction (rolled back)
# - Forbidden patterns (INSERT, UPDATE, DELETE, DROP, etc.) are rejected
# - Results truncated to prevent context overflow
#
class SchemaExplorerTool < RubyLLM::Tool
  include SqlErrorSanitizer

  include Tools::ConnectionConfigBuilder
  include Tools::SqlQueryExecutor

  MAX_RESULT_ROWS = 50
  MAX_RESULT_LENGTH = 8_000

  param :sql, desc: "A read-only SQL query (SELECT only) to explore the database structure and data"

  def self.for_sql_database(sql_database)
    new(sql_database)
  end

  def initialize(sql_database)
    super()
    @sql_database = sql_database
  end

  def name
    "explore_database"
  end

  def description
    "Execute a read-only SQL query to explore the database. Use SELECT queries only. " \
      "Good for: checking row counts, sampling data, finding distinct values, " \
      "discovering indexes, and understanding data patterns."
  end

  def execute(sql:)
    validate_sql!(sql)
    result = execute_sql(sql)
    format_result(result)
  rescue Tools::QuerySecurityError => e
    "Security error: #{e.message}"
  rescue StandardError => e
    "Query failed: #{sanitize_error(e.message)}"
  end

  private

  # Override sql_database accessor for SqlQueryExecutor
  attr_reader :sql_database

  def validate_sql!(sql)
    raise Tools::QuerySecurityError, "Only SELECT queries are allowed." unless sql.strip.match?(/\A(SELECT|WITH)\b/i)

    Tools::SqlQueryService::FORBIDDEN_PATTERNS.each do |pattern|
      raise Tools::QuerySecurityError, "Query contains forbidden operations." if sql.match?(pattern)
    end
  end

  def format_result(result)
    return "No results." if empty_result?(result)

    rows = result.is_a?(Array) ? result : [result]
    build_output(rows)
  end

  def empty_result?(result)
    result.nil? || (result.respond_to?(:empty?) && result.empty?)
  end

  def build_output(rows)
    truncated = rows.first(MAX_RESULT_ROWS)
    output = truncated.map(&:to_json).join("\n")

    output = "#{output[0...MAX_RESULT_LENGTH]}\n... (truncated)" if output.length > MAX_RESULT_LENGTH
    output += "\n(Showing #{MAX_RESULT_ROWS} of #{rows.size} rows)" if rows.size > MAX_RESULT_ROWS

    output
  end
end
