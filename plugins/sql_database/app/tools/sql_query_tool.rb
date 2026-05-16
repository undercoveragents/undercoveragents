# frozen_string_literal: true

# RubyLLM tool that queries a SQL database using natural language.
#
# This is a generic, tool-driven implementation: the description, schema, query
# instructions, and connection details all come from the Tool / Tools::SqlQuery
# record and its associated Connector.
#
# Each enabled SQL Query tool produces its own SqlQueryTool instance so that
# multiple databases can be offered to the LLM simultaneously.
#
# Usage:
#   tool_record = Tool.sql_queries.enabled.find(id)
#   tool = SqlQueryTool.for_tool(tool_record)
#   chat.with_tool(tool)
#   chat.ask("How many users are there?")
#
class SqlQueryTool < RubyLLM::Tool
  DEFAULT_TOOL_PROMPT = "Query this SQL database using natural language. " \
                        "Ask questions about the data and get answers."

  param :question, desc: "The natural language question to answer by querying the database"
  param :limit, type: :integer,
                desc: "Maximum number of records to return. Only affects list queries, not aggregations.",
                required: false

  def self.for_tool(tool_record, agent: nil, parent_chat: nil)
    raise ArgumentError, "Expected a SQL Query tool" unless tool_record.toolable.is_a?(Tools::SqlQuery)

    new(tool_record, agent:, parent_chat:)
  end

  def initialize(tool_record, agent: nil, parent_chat: nil)
    super()
    @tool_record = tool_record
    @sql_query = tool_record.toolable
    @connector = @sql_query.connector
    @sql_database = @connector
    @agent = agent
    @parent_chat = parent_chat
  end

  def name
    base = @tool_record.name
                       .unicode_normalize(:nfkd)
                       .encode("ASCII", replace: "")
                       .gsub(/[^a-zA-Z0-9_-]/, "_").squeeze("_")
                       .gsub(/\A_|_\z/, "")
                       .downcase

    "sql_query_#{base}"
  end

  def description
    @sql_query.effective_instructions
  end

  def execute(question:, limit: nil)
    effective_limit = limit || @sql_database.max_results
    original_max = @sql_database.max_results
    @sql_database.max_results = effective_limit

    llm_config = resolve_llm_config
    service = Tools::SqlQueryService.new(
      @sql_database,
      sql_query: @sql_query,
      parent_chat: @parent_chat,
      **llm_config,
    )
    result = service.query(question)

    format_result(result)
  rescue StandardError => e
    Rails.logger.error "[SqlQueryTool] Query failed for tool '#{@tool_record.name}': #{e.message}"
    "I couldn't execute that query. Error: #{e.message}"
  ensure
    @sql_database.max_results = original_max if original_max
  end

  private

  def resolve_llm_config
    if @sql_query.use_custom_llm_config?
      context = @sql_query.llm_connector&.build_context
      { model: @sql_query.model_id, temperature: @sql_query.temperature, llm_context: context }
    elsif @agent
      context = @agent.resolve_llm_context
      { model: @agent.resolved_model_id, temperature: @agent.temperature, llm_context: context }
    elsif inherited_model_id.present? || inherited_llm_context.present?
      { model: inherited_model_id, llm_context: inherited_llm_context }.compact
    else
      {}
    end
  end

  def inherited_model_id
    @parent_chat&.model&.model_id.presence || @parent_chat&.agent&.resolved_model_id.presence
  end

  def inherited_llm_context
    return unless @parent_chat

    @parent_chat.context.presence || @parent_chat.agent&.resolve_llm_context
  end

  def format_result(result)
    return "No results found." if result.nil? || (result.respond_to?(:empty?) && result.empty?)

    case result
    when Array
      result.to_json
    else
      result.inspect
    end
  end
end
