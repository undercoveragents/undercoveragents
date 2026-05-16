# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpServerConnectionTester do
  describe "#call" do
    let(:mock_client) { instance_double("RubyLLM::MCP::Client") } # rubocop:disable RSpec/VerifiedDoubleReference
    let(:mock_tool) { double("Tool", name: "read_file", description: "Reads a file") } # rubocop:disable RSpec/VerifiedDoubles

    before do
      allow(RubyLLM::MCP).to receive(:client).and_return(mock_client)
      allow(mock_client).to receive(:stop)
    end

    context "with STDIO transport" do
      let(:params) do
        {
          transport_type: "stdio",
          command: "npx",
          args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
          request_timeout: 8000,
        }
      end

      it "returns success with tool count on successful connection" do
        allow(mock_client).to receive(:tools).and_return([mock_tool])

        result = described_class.new(params).call

        expect(result.success?).to be(true)
        expect(result.message).to include("1 tool(s) available")
        expect(result.details[:tools_count]).to eq(1)
        expect(result.details[:tool_names]).to eq(["read_file"])
      end

      it "ignores client stop failures" do
        allow(mock_client).to receive(:stop).and_raise(StandardError, "stop failed")

        expect { described_class.new(params).send(:stop_client, mock_client) }.not_to raise_error
      end

      it "initializes client with correct STDIO config" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            transport_type: :stdio,
            config: hash_including(
              command: "npx",
              args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
            ),
          ),
        )
      end

      it "includes env vars in STDIO config" do
        params_with_env = params.merge(env_vars: { "DEBUG" => "1" })
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params_with_env).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: hash_including(env: { "DEBUG" => "1" }),
          ),
        )
      end
    end

    context "with SSE transport" do
      let(:params) do
        {
          transport_type: "sse",
          url: "https://mcp.example.com/sse",
          request_timeout: 8000,
        }
      end

      it "initializes client with correct SSE config" do
        allow(mock_client).to receive(:tools).and_return([mock_tool])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            transport_type: :sse,
            config: hash_including(url: "https://mcp.example.com/sse"),
          ),
        )
      end

      it "includes headers when provided" do
        params_with_headers = params.merge(headers: { "Authorization" => "Bearer token" })
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params_with_headers).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: hash_including(headers: { "Authorization" => "Bearer token" }),
          ),
        )
      end
    end

    context "with Streamable HTTP transport" do
      let(:params) do
        {
          transport_type: "streamable_http",
          url: "https://mcp.example.com/mcp",
          request_timeout: 8000,
        }
      end

      it "initializes client with streamable type" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(transport_type: :streamable),
        )
      end

      it "includes OAuth config when enabled" do
        oauth_params = params.merge(
          oauth_enabled: "true", oauth_client_id: "client-id",
          oauth_client_secret: "client-secret", oauth_scope: "mcp:read",
          oauth_grant_type: "client_credentials",
        )
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(oauth_params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: hash_including(
              oauth: hash_including(
                client_id: "client-id",
                client_secret: "client-secret",
                scope: "mcp:read",
                grant_type: :client_credentials,
              ),
            ),
          ),
        )
      end

      it "does not include OAuth when disabled" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params.merge(oauth_enabled: "false")).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: hash_not_including(:oauth),
          ),
        )
      end
    end

    context "when multiple tools are returned" do
      let(:params) { { transport_type: "stdio", command: "npx", request_timeout: 8000 } }
      let(:tools) do
        [
          double("Tool", name: "read_file"), # rubocop:disable RSpec/VerifiedDoubles
          double("Tool", name: "write_file"),   # rubocop:disable RSpec/VerifiedDoubles
          double("Tool", name: "list_dir"),     # rubocop:disable RSpec/VerifiedDoubles
        ]
      end

      it "reports all tools" do
        allow(mock_client).to receive(:tools).and_return(tools)

        result = described_class.new(params).call

        expect(result.details[:tools_count]).to eq(3)
        expect(result.details[:tool_names]).to eq(["read_file", "write_file", "list_dir"])
      end
    end

    context "when connection fails" do
      let(:params) { { transport_type: "stdio", command: "nonexistent-command", request_timeout: 8000 } }

      it "returns failure on transport error" do
        allow(RubyLLM::MCP).to receive(:client).and_raise(
          RubyLLM::MCP::Errors::TransportError.new(message: "Connection refused"),
        )

        result = described_class.new(params).call

        expect(result.success?).to be(false)
        expect(result.message).to include("Transport error")
      end

      it "returns failure on timeout" do
        allow(RubyLLM::MCP).to receive(:client).and_raise(
          RubyLLM::MCP::Errors::TimeoutError.new(message: "Timed out after 8000ms"),
        )

        result = described_class.new(params).call

        expect(result.success?).to be(false)
        expect(result.message).to include("timed out")
      end

      it "returns failure on generic error" do
        allow(RubyLLM::MCP).to receive(:client).and_raise(StandardError.new("Unknown error"))

        result = described_class.new(params).call

        expect(result.success?).to be(false)
        expect(result.message).to include("Unknown error")
      end
    end

    context "with args as string" do
      let(:params) do
        {
          transport_type: "stdio",
          command: "npx",
          args: "-y\n@modelcontextprotocol/server-filesystem\n/tmp",
          request_timeout: 8000,
        }
      end

      it "parses newline-separated args" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: hash_including(
              args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
            ),
          ),
        )
      end
    end

    context "with args as JSON array string" do
      let(:params) do
        {
          transport_type: "stdio",
          command: "npx",
          args: '["-y", "@mcp/server"]',
          request_timeout: 8000,
        }
      end

      it "parses JSON array args" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: hash_including(args: ["-y", "@mcp/server"]),
          ),
        )
      end
    end

    context "with headers as JSON string" do
      let(:params) do
        {
          transport_type: "sse",
          url: "https://mcp.example.com/sse",
          headers: '{"Authorization": "Bearer token"}',
          request_timeout: 8000,
        }
      end

      it "parses JSON hash for headers" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: hash_including(headers: { "Authorization" => "Bearer token" }),
          ),
        )
      end
    end

    context "with invalid JSON for headers" do
      let(:params) do
        {
          transport_type: "sse",
          url: "https://mcp.example.com/sse",
          headers: "not-valid-json",
          request_timeout: 8000,
        }
      end

      it "falls back to empty hash" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: hash_including(headers: {}),
          ),
        )
      end
    end

    context "with env_vars as hash" do
      let(:params) do
        {
          transport_type: "stdio",
          command: "npx",
          env_vars: { "KEY" => "value" },
          request_timeout: 8000,
        }
      end

      it "passes hash directly" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: hash_including(env: { "KEY" => "value" }),
          ),
        )
      end
    end

    context "with http_version" do
      let(:params) do
        {
          transport_type: "sse",
          url: "https://mcp.example.com/sse",
          http_version: "http2",
          request_timeout: 8000,
        }
      end

      it "includes version symbol" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: hash_including(version: :http2),
          ),
        )
      end
    end

    context "with all OAuth fields" do
      let(:params) do
        {
          transport_type: "streamable_http",
          url: "https://mcp.example.com/mcp",
          oauth_enabled: "1",
          oauth_client_id: "id",
          oauth_client_secret: "secret",
          oauth_issuer: "https://issuer.example.com",
          oauth_scope: "read write",
          oauth_redirect_uri: "https://redirect.example.com/callback",
          oauth_grant_type: "authorization_code",
          request_timeout: 8000,
        }
      end

      it "includes all OAuth fields" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: hash_including(
              oauth: {
                client_id: "id",
                client_secret: "secret",
                issuer: "https://issuer.example.com",
                scope: "read write",
                redirect_uri: "https://redirect.example.com/callback",
                grant_type: :authorization_code,
              },
            ),
          ),
        )
      end
    end

    context "with OAuth enabled but no grant_type (nil &.to_sym)" do
      let(:params) do
        {
          transport_type: "streamable_http",
          url: "https://mcp.example.com/mcp",
          oauth_enabled: "true",
          oauth_client_id: "client-id",
          oauth_client_secret: "secret",
          request_timeout: 8000,
        }
      end

      it "omits grant_type from OAuth config when not provided" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: hash_including(
              oauth: hash_not_including(:grant_type),
            ),
          ),
        )
      end
    end

    context "with env_vars as non-Hash non-String (parse_hash else branch)" do
      let(:params) do
        {
          transport_type: "stdio",
          command: "npx",
          env_vars: 42, # Integer — neither Hash nor String
          request_timeout: 8000,
        }
      end

      it "treats non-hash/non-string env_vars as empty hash" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: hash_including(env: {}),
          ),
        )
      end
    end

    context "without transport_type" do
      let(:params) { { command: "npx", request_timeout: 8000 } }

      it "defaults to stdio" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(transport_type: :stdio),
        )
      end
    end

    context "with default timeout" do
      let(:params) { { transport_type: "stdio", command: "npx" } }

      it "uses DEFAULT_TIMEOUT" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(request_timeout: 15_000),
        )
      end
    end

    context "with STDIO missing args and env" do
      let(:params) { { transport_type: "stdio", command: "npx", request_timeout: 8000 } }

      it "omits args and env from config" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            config: { command: "npx" },
          ),
        )
      end
    end

    context "with a custom/unknown transport type" do
      let(:params) { { transport_type: "custom_ws", command: "npx", request_timeout: 8000 } }

      it "converts transport type to symbol and passes empty config" do
        allow(mock_client).to receive(:tools).and_return([])

        described_class.new(params).call

        expect(RubyLLM::MCP).to have_received(:client).with(
          hash_including(
            transport_type: :custom_ws,
            config: {},
          ),
        )
      end
    end

    it "stops the client after testing" do
      params = { transport_type: "stdio", command: "npx", request_timeout: 8000 }
      allow(mock_client).to receive(:tools).and_return([])

      described_class.new(params).call

      expect(mock_client).to have_received(:stop)
    end
  end
end
