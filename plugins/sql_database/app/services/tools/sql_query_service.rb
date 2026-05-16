# frozen_string_literal: true

module Tools
  # Raised when generated SQL contains forbidden operations.
  class QuerySecurityError < StandardError; end

  # Service that converts a natural language question into a SQL SELECT query,
  # executes it read-only against the connector's database, and returns results.
  #
  # Safety:
  # - Only SELECT statements are allowed (validated before execution)
  # - Executes inside a READ-ONLY transaction that is always rolled back
  # - Dangerous keywords (INSERT, UPDATE, DELETE, DROP, etc.) are rejected
  #
  # All configuration (schema, instructions, max results) comes from the
  # SqlDatabase connector — nothing is hardcoded.
  #
  # Usage:
  #   connector = Connector.find(1)
  #   service = Tools::SqlQueryService.new(connector)
  #   result = service.query("How many users are there?")
  #   # => [{"count" => 42}]
  #
  class SqlQueryService
    include SqlQueryExecutor

    DEFAULT_MODEL = nil
    DEFAULT_TEMPERATURE = nil

    # SQL keywords/statements that are never allowed in generated queries
    FORBIDDEN_PATTERNS = [
      /\b(INSERT|UPDATE|DELETE|DROP|TRUNCATE|ALTER|CREATE|GRANT|REVOKE)\b/i,
      /\b(COPY|EXECUTE|CALL|DO)\b/i,
      /\b(SET\s+(?!TRANSACTION\s+READ\s+ONLY))/i,
      /;\s*\S/, # Multiple statements (semicolon followed by non-whitespace)
    ].freeze

    attr_reader :sql_database

    def initialize(sql_database, **options)
      @sql_database = sql_database
      @sql_query = options[:sql_query]
      @model = options.fetch(:model, DEFAULT_MODEL)
      @temperature = options.fetch(:temperature, DEFAULT_TEMPERATURE)
      @llm_context = options[:llm_context]
      @parent_chat = options[:parent_chat]
      @extra_instructions = options[:extra_instructions]
    end

    # @param question [String] natural language question
    # @return [Array<Hash>] query result rows
    def query(question)
      sql = generate_sql(question)
      execute_sql(sql)
    end

    # @param question [String] natural language question
    # @return [String] the generated SQL query
    def generate_sql(question)
      chat = build_llm_chat
      response = chat.ask(question)
      extract_sql(response.content)
    end

    def schema_text
      @schema_text ||= SqlSchemaBuilder.call(@sql_database, sql_query: @sql_query)
    end

    private

    # ── Chat Construction ─────────────────────────────────────────

    def build_llm_chat
      BuiltinAgents::Runner.build_chat!(
        builtin_key: "sql_query_agent",
        model_id: @model,
        temperature: @temperature.nil? ? Agent::UNSET : @temperature,
        llm_context: @llm_context,
        title: "SQL Query",
        parent_chat: @parent_chat,
        input_values: {
          adapter_label: @sql_database.adapter_type.titleize,
          schema_text:,
          extra_instructions_block: @extra_instructions.to_s,
          max_results: @sql_database.max_results,
        },
      )
    end

    def extract_sql(text)
      sql = text.strip
      sql = sql.gsub(/\A```(?:sql)?\s*\n?/, "").gsub(/\n?```\s*\z/, "")
      sql = sql.chomp(";")
      sql.strip
    end

    # ── SQL Safety ────────────────────────────────────────────────

    def validate_sql!(sql)
      unless sql.strip.match?(/\A(SELECT|WITH)\b/i)
        raise QuerySecurityError, "Only SELECT queries are allowed. Got: #{sql[0..50]}"
      end

      violations = []
      FORBIDDEN_PATTERNS.each do |pattern|
        if (match = sql.match(pattern))
          violations << match[0].strip
        end
      end

      return if violations.empty?

      raise QuerySecurityError, "Generated SQL contains forbidden operations: #{violations.uniq.join(", ")}"
    end
  end
end
