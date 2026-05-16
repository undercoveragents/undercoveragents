# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("mcp_server") do
  name "MCP Server"
  version "1.0.0"
  author "Undercover Agents"
  description "Connect to MCP servers and expose their tools to agents. " \
              "Supports STDIO, SSE, and Streamable HTTP transports."
  icon "fa-solid fa-server"
  category [:connector, :tool]
  add_connector "McpServer"
  add_tool "McpServer"
end
