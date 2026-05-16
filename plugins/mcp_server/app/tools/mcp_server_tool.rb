# frozen_string_literal: true

class McpServerTool
  # Unlike SqlQueryTool (which is a single RubyLLM::Tool), an MCP tool record
  # expands into multiple RubyLLM::MCP::Tool instances — one per selected tool.
  # This class provides the factory pattern but returns an array of tool instances.

  def self.for_tool(tool_record)
    raise ArgumentError, "Expected an MCP Server tool" unless tool_record.toolable.is_a?(Tools::McpServer)

    new(tool_record).resolve_tools
  end

  def initialize(tool_record)
    @tool_record = tool_record
    @mcp_tool = tool_record.toolable
    @mcp_server = @mcp_tool.mcp_server
  end

  def resolve_tools
    return [] unless @mcp_server

    client_config = @mcp_server.build_client_config
    client = RubyLLM::MCP.client(**client_config)
    all_tools = client.tools

    filter_selected_tools(all_tools)
  rescue StandardError => e
    Rails.logger.error "[McpServerTool] Failed to resolve tools for '#{@tool_record.name}': #{e.message}"
    []
  end

  private

  def filter_selected_tools(all_tools)
    selected_names = @mcp_tool.selected_tool_names
    return all_tools if selected_names.empty?

    all_tools.select { |t| selected_names.include?(t.name) }
  end
end
