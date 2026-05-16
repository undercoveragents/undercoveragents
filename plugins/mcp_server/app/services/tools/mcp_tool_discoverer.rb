# frozen_string_literal: true

module Tools
  class McpToolDiscoverer
    Result = Data.define(:success?, :message, :tools)

    def initialize(mcp_server_connector)
      @mcp_server = mcp_server_connector
    end

    def call
      client_config = @mcp_server.build_client_config
      client = RubyLLM::MCP.client(**client_config)
      tool_list = build_tool_list(client.tools)

      Result.new(
        success?: true,
        message: "Discovered #{tool_list.size} tool(s)",
        tools: tool_list,
      )
    rescue RubyLLM::MCP::Errors::TransportError => e
      failure("Transport error: #{e.message.to_s.truncate(300)}")
    rescue RubyLLM::MCP::Errors::TimeoutError => e
      failure("Connection timed out: #{e.message.to_s.truncate(300)}")
    rescue StandardError => e
      failure(e.message.to_s.truncate(300))
    ensure
      stop_client(client)
    end

    private

    def stop_client(client)
      client&.stop
    rescue StandardError
      nil
    end

    def build_tool_list(mcp_tools)
      mcp_tools.map do |t|
        {
          "name" => t.name,
          "description" => t.description.to_s.truncate(500),
        }
      end
    end

    def failure(message)
      Result.new(success?: false, message:, tools: [])
    end
  end
end
