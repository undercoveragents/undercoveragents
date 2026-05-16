# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ConnectorMcpServerController" do
  describe "POST /connectors/mcp_server/test_connection" do
    let(:success_result) do
      BaseConnectionTester::Result.new(
        success?: true,
        message: "Connected successfully — 3 tool(s) available",
        details: { tools_count: 3, tool_names: ["read_file", "write_file", "list_dir"] },
      )
    end

    let(:failure_result) do
      BaseConnectionTester::Result.new(
        success?: false,
        message: "Transport error: Connection refused",
        details: {},
      )
    end

    before do
      allow(McpServerConnectionTester).to receive(:new).and_return(
        instance_double(McpServerConnectionTester, call: success_result),
      )
    end

    it "returns success with tool info for STDIO transport" do
      post "/admin/connectors/mcp_server/test_connection", params: {
        mcp_server: {
          transport_type: "stdio",
          command: "npx",
          args_text: "-y\n@modelcontextprotocol/server-filesystem\n/tmp",
          request_timeout: 8000,
        },
      }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(response.parsed_body.dig("details", "tools_count")).to eq(3)
      expect(response.parsed_body.dig("details", "tool_names")).to include("read_file")
    end

    it "returns failure when MCP connection fails" do
      allow(McpServerConnectionTester).to receive(:new).and_return(
        instance_double(McpServerConnectionTester, call: failure_result),
      )

      post "/admin/connectors/mcp_server/test_connection", params: {
        mcp_server: { transport_type: "stdio", command: "bad-cmd", request_timeout: 8000 },
      }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["message"]).to include("Transport error")
    end

    it "returns 500 on unexpected error" do
      allow(McpServerConnectionTester).to receive(:new).and_raise(StandardError.new("boom"))

      post "/admin/connectors/mcp_server/test_connection", params: {
        mcp_server: { transport_type: "stdio", command: "npx", request_timeout: 8000 },
      }

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["message"]).to eq("boom")
    end
  end
end
