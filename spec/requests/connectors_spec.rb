# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connectors" do
  describe "GET /connectors" do
    it "returns a successful response" do
      get admin_connectors_path
      expect(response).to have_http_status(:ok)
    end

    it "displays the connectors heading" do
      get admin_connectors_path
      expect(response.body).to include("Connectors")
    end

    it "displays the empty state when no connectors exist" do
      get admin_connectors_path
      expect(response.body).to include("No connectors yet")
    end

    context "with existing connectors" do
      let(:mcp_connector) { create(:connector, :mcp_server, name: "Filesystem MCP") }
      let(:llm_connector) { create(:connector, :llm_provider, name: "OpenAI Production") }

      it "lists all connectors" do
        mcp_connector
        llm_connector
        get admin_connectors_path
        expect(response.body).to include("Filesystem MCP")
        expect(response.body).to include("OpenAI Production")
      end
    end
  end

  describe "GET /connectors/new" do
    it "returns a successful response" do
      get new_admin_connector_path
      expect(response).to have_http_status(:ok)
    end

    it "shows connector type selection" do
      get new_admin_connector_path
      expect(response.body).to include("SQL Database")
      expect(response.body).to include("LLM Provider")
      expect(response.body).to include("Brave Search")
    end

    it "shows LLM Provider form when type=llm_provider" do
      get new_admin_connector_path(type: "llm_provider")
      expect(response.body).to include("Provider")
      expect(response.body).to include("LLM Provider")
    end

    it "shows Brave Search form when type=brave_search" do
      get new_admin_connector_path(type: "brave_search")
      expect(response.body).to include("Brave Search Configuration")
      expect(response.body).to include("API Key")
    end

    it "shows MCP Server form when type=mcp_server" do
      get new_admin_connector_path(type: "mcp_server")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Transport Type")
      expect(response.body).to include("Transport Configuration")
    end

    it "shows MCP Server type card on the type selection page" do
      get new_admin_connector_path
      expect(response.body).to include("MCP Server")
    end
  end

  describe "POST /connectors" do
    context "with LLM Provider connector" do
      let(:valid_params) do
        {
          connector_type: "llm_provider",
          connector: { name: "My OpenAI", description: "Production OpenAI key" },
          llm_provider: {
            provider: "openai",
            api_key: "sk-test-12345",
            request_timeout: 120,
            max_retries: 3,
            retry_interval: 0.1,
            retry_backoff_factor: 2,
            retry_interval_randomness: 0.5,
          },
        }
      end

      it "creates a new LLM Provider connector" do
        expect { post admin_connectors_path, params: valid_params }
          .to change(Connector, :count).by(1)
          .and change(Connectors::LlmProvider, :count).by(1)
      end

      it "redirects to the connector show page" do
        post admin_connectors_path, params: valid_params
        expect(response).to redirect_to(admin_connector_path(Connector.last))
      end

      it "saves the provider configuration" do
        post admin_connectors_path, params: valid_params
        llm_provider = Connectors::LlmProvider.last
        expect(llm_provider.provider).to eq("openai")
        expect(llm_provider.api_key).to eq("sk-test-12345")
      end
    end

    context "with MCP Server connector (stdio)" do
      let(:valid_params) do
        {
          connector_type: "mcp_server",
          connector: { name: "Filesystem MCP", description: "Local filesystem access" },
          mcp_server: {
            transport_type: "stdio",
            command: "npx",
            args_text: "-y\n@modelcontextprotocol/server-filesystem\n/tmp",
            env_vars_text: "NODE_ENV=production\nDEBUG=true",
            request_timeout: 8000,
          },
        }
      end

      it "creates a new MCP connector" do
        expect { post admin_connectors_path, params: valid_params }
          .to change(Connector, :count).by(1)
          .and change(Connectors::McpServer, :count).by(1)
      end

      it "redirects to the connector show page" do
        post admin_connectors_path, params: valid_params
        expect(response).to redirect_to(admin_connector_path(Connector.last))
      end

      it "parses args and env vars from text fields" do
        post admin_connectors_path, params: valid_params
        mcp = Connectors::McpServer.last
        expect(mcp.args).to eq(["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])
        expect(mcp.env_vars).to eq({ "NODE_ENV" => "production", "DEBUG" => "true" })
      end
    end

    context "with MCP Server connector (stdio) with malformed env_vars_text" do
      let(:malformed_params) do
        {
          connector_type: "mcp_server",
          connector: { name: "Malformed MCP", description: "Malformed env vars" },
          mcp_server: {
            transport_type: "stdio",
            command: "npx",
            args_text: "-y\n@mcp/server",
            env_vars_text: "VALID_KEY=value\n\nBAD_LINE_NO_VALUE=\n=no_key",
            request_timeout: 8000,
          },
        }
      end

      it "skips blank lines and lines without valid key=value pairs" do
        post admin_connectors_path, params: malformed_params
        mcp = Connectors::McpServer.last
        expect(mcp.env_vars).to eq({ "VALID_KEY" => "value" })
      end
    end

    context "with MCP Server connector (SSE)" do
      let(:valid_params) do
        {
          connector_type: "mcp_server",
          connector: { name: "Remote MCP SSE", description: "SSE transport" },
          mcp_server: {
            transport_type: "sse",
            url: "https://mcp.example.com/sse",
            http_version: "http2",
            headers_text: "Authorization=Bearer test-token\nX-Custom=value",
            request_timeout: 15_000,
          },
        }
      end

      it "creates a new SSE connector" do
        expect { post admin_connectors_path, params: valid_params }
          .to change(Connector, :count).by(1)
        mcp = Connectors::McpServer.last
        expect(mcp.transport_type).to eq("sse")
        expect(mcp.url).to eq("https://mcp.example.com/sse")
        expect(mcp.headers).to eq({ "Authorization" => "Bearer test-token", "X-Custom" => "value" })
      end
    end

    context "with MCP Server connector (streamable_http with OAuth)" do
      let(:valid_params) do
        {
          connector_type: "mcp_server",
          connector: { name: "OAuth MCP", description: "With OAuth" },
          mcp_server: {
            transport_type: "streamable_http",
            url: "https://mcp.example.com/mcp",
            http_version: "http1",
            headers_text: "",
            oauth_enabled: true,
            oauth_client_id: "my-client",
            oauth_client_secret: "my-secret",
            oauth_scope: "mcp:read mcp:write",
            oauth_grant_type: "authorization_code",
            request_timeout: 10_000,
          },
        }
      end

      it "creates a streamable_http connector with OAuth" do
        expect { post admin_connectors_path, params: valid_params }
          .to change(Connector, :count).by(1)
        mcp = Connectors::McpServer.last
        expect(mcp.transport_type).to eq("streamable_http")
        expect(mcp.oauth_enabled).to be(true)
        expect(mcp.oauth_client_id).to eq("my-client")
      end
    end

    context "with invalid MCP Server params" do
      it "renders new with errors when command is missing for stdio" do
        post admin_connectors_path, params: {
          connector_type: "mcp_server",
          connector: { name: "Broken MCP" },
          mcp_server: { transport_type: "stdio", command: "", request_timeout: 8000 },
        }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "renders new with errors when url is missing for sse" do
        post admin_connectors_path, params: {
          connector_type: "mcp_server",
          connector: { name: "Broken MCP" },
          mcp_server: { transport_type: "sse", url: "", request_timeout: 8000 },
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with Authentication connector" do
      let(:valid_params) do
        {
          connector_type: "authentication",
          connector: { name: "Keycloak", description: "SSO Provider" },
          authentication: {
            provider: "keycloak",
            site_url: "https://auth.example.com",
            realm: "myrealm",
            client_id: "my-client",
            client_secret: "secret123",
          },
        }
      end

      it "creates a new Authentication connector" do
        expect { post admin_connectors_path, params: valid_params }
          .to change(Connector, :count).by(1)
          .and change(Connectors::Authentication, :count).by(1)
      end
    end

    context "with Brave Search connector" do
      let(:valid_params) do
        {
          connector_type: "brave_search",
          connector: { name: "Brave Search", description: "Authenticated web search" },
          brave_search: { api_key: "brave-secret-key" },
        }
      end

      it "creates a new Brave Search connector" do
        expect { post admin_connectors_path, params: valid_params }
          .to change(Connector, :count).by(1)
          .and change(Connectors::BraveSearch, :count).by(1)
      end

      it "saves the encrypted api key" do
        post admin_connectors_path, params: valid_params

        expect(Connectors::BraveSearch.last.api_key).to eq("brave-secret-key")
      end
    end

    context "with an unknown connector_type" do
      it "builds a connector without type-specific params and attempts to save" do
        post admin_connectors_path, params: {
          connector_type: "nonexistent_type_xyz",
          connector: { name: "Unknown Type Connector" },
        }
        # The connector will fail to save due to unregistered connector_type validation,
        # and the form is re-rendered with errors.
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /connectors/:id" do
    let(:connector) { create(:connector, :llm_provider, name: "Test Connector") }

    it "returns a successful response" do
      get admin_connector_path(connector)
      expect(response).to have_http_status(:ok)
    end

    it "displays the connector details" do
      get admin_connector_path(connector)
      expect(response.body).to include("Test Connector")
      expect(response.body).to include("Edit")
    end

    it "shows delete and omits the old connector actions" do
      get admin_connector_path(connector)
      expect(response.body).to include("Delete Connector")
      expect(response.body).not_to include("Edit Connection")
      expect(response.body).not_to include(toggle_admin_connector_path(connector))
    end

    context "with an LLM Provider connector" do
      let(:llm_connector) { create(:connector, :llm_provider, name: "My OpenAI") }

      it "displays the LLM provider details" do
        get admin_connector_path(llm_connector)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("My OpenAI")
        expect(response.body).to include("LLM Provider")
        expect(response.body).to include("OpenAI")
      end
    end

    context "with an MCP Server connector (stdio)" do
      let(:mcp_connector) do
        create(:connector, :mcp_server, name: "FS MCP",
                                        args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
                                        env_vars: { "GITHUB_TOKEN" => "ghp_test" },)
      end

      it "displays the MCP server details" do
        get admin_connector_path(mcp_connector)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("FS MCP")
        expect(response.body).to include("MCP Server")
        expect(response.body).to include("STDIO")
      end

      it "displays args and env vars" do
        get admin_connector_path(mcp_connector)
        expect(response.body).to include("Arguments")
        expect(response.body).to include("Env Variables")
      end
    end

    context "with an MCP Server connector (SSE with OAuth)" do
      let(:mcp_connector) do
        create(:connector, :mcp_server, name: "SSE MCP",
                                        transport_type: "sse",
                                        command: nil,
                                        url: "https://mcp.example.com/sse",
                                        http_version: "http2",
                                        headers: { "Authorization" => "Bearer token" },
                                        oauth_enabled: true,
                                        oauth_client_id: "my-client",
                                        oauth_grant_type: "client_credentials",)
      end

      it "displays HTTP transport details" do
        get admin_connector_path(mcp_connector)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("SSE MCP")
        expect(response.body).to include("HTTP Version")
        expect(response.body).to include("Custom Headers")
        expect(response.body).to include("OAuth")
      end
    end

    context "with a Brave Search connector" do
      let(:brave_connector) { create(:connectors_brave_search, name: "Brave Search Connector") }

      it "displays the Brave Search details" do
        get admin_connector_path(brave_connector)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Brave Search Connector")
        expect(response.body).to include("Brave Search")
        expect(response.body).to include("Configured")
      end
    end
  end

  describe "GET /connectors/:id/edit" do
    let(:connector) { create(:connector, :llm_provider, name: "Test Provider") }

    it "returns a successful response" do
      get edit_admin_connector_path(connector)
      expect(response).to have_http_status(:ok)
    end

    context "with an LLM Provider connector" do
      let(:llm_connector) { create(:connector, :llm_provider, name: "My OpenAI") }

      it "displays the LLM provider edit form" do
        get edit_admin_connector_path(llm_connector)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("My OpenAI")
        expect(response.body).to include("Provider")
      end
    end

    context "with an MCP Server connector" do
      let(:mcp_connector) { create(:connector, :mcp_server, name: "Edit MCP") }

      it "displays the MCP server edit form" do
        get edit_admin_connector_path(mcp_connector)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Edit MCP")
        expect(response.body).to include("Transport Type")
      end
    end
  end

  describe "PATCH /connectors/:id" do
    context "with an MCP Server connector" do
      let(:mcp_connector) { create(:connector, :mcp_server, name: "Old MCP Name") }

      it "updates the connector name and settings" do
        patch admin_connector_path(mcp_connector), params: {
          connector_type: "mcp_server",
          connector: { name: "New MCP Name" },
          mcp_server: {
            transport_type: "stdio",
            command: "uvx",
            args_text: "--from\ngithub-mcp-server\ngithub-mcp-server",
            env_vars_text: "TOKEN=abc123",
            request_timeout: 10_000,
          },
        }
        expect(response).to redirect_to(admin_connector_path(mcp_connector.reload))
        expect(mcp_connector.name).to eq("New MCP Name")
        mcp = mcp_connector.reload
        expect(mcp.command).to eq("uvx")
        expect(mcp.args).to eq(["--from", "github-mcp-server", "github-mcp-server"])
        expect(mcp.env_vars).to eq({ "TOKEN" => "abc123" })
      end

      it "infers connector type from existing record" do
        patch admin_connector_path(mcp_connector), params: {
          connector: { name: "Inferred MCP" },
          mcp_server: {
            transport_type: "stdio",
            command: "npx",
            args_text: "-y\ntest-server",
            request_timeout: 8000,
          },
        }
        expect(response).to redirect_to(admin_connector_path(mcp_connector.reload))
        expect(mcp_connector.name).to eq("Inferred MCP")
      end

      it "re-renders edit on invalid params" do
        patch admin_connector_path(mcp_connector), params: {
          connector_type: "mcp_server",
          connector: { name: "" },
          mcp_server: { transport_type: "stdio", command: "", request_timeout: 8000 },
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /connectors/transport_fields" do
    it "returns STDIO transport fields" do
      get admin_transport_fields_connectors_path(transport_type: "stdio")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Command")
    end

    it "returns SSE transport fields" do
      get admin_transport_fields_connectors_path(transport_type: "sse")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Server URL")
    end

    it "returns Streamable HTTP transport fields" do
      get admin_transport_fields_connectors_path(transport_type: "streamable_http")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Server URL")
    end
  end

  describe "DELETE /connectors/:id" do
    let!(:connector) { create(:connector, :llm_provider) }

    it "destroys the connector" do
      expect { delete admin_connector_path(connector) }
        .to change(Connector, :count).by(-1)
    end

    it "redirects to the index" do
      delete admin_connector_path(connector)
      expect(response).to redirect_to(admin_connectors_path)
    end
  end

  describe "PATCH /connectors/:id/toggle" do
    let(:connector) { create(:connector, :llm_provider, enabled: false) }

    it "toggles the enabled status" do
      patch toggle_admin_connector_path(connector)
      expect(connector.reload.enabled).to be(true)
    end

    it "redirects to the index" do
      patch toggle_admin_connector_path(connector)
      expect(response).to redirect_to(admin_connectors_path)
    end

    context "when connector is enabled" do
      let(:enabled_connector) { create(:connector, :llm_provider, enabled: true) }

      it "disables the connector" do
        patch toggle_admin_connector_path(enabled_connector)
        expect(enabled_connector.reload.enabled).to be(false)
      end
    end
  end

  describe "GET /connectors/provider_fields" do
    it "returns the provider fields partial for openai" do
      get admin_provider_fields_connectors_path(provider: "openai")
      expect(response).to have_http_status(:ok)
    end

    it "returns provider fields for anthropic" do
      get admin_provider_fields_connectors_path(provider: "anthropic")
      expect(response).to have_http_status(:ok)
    end

    it "requires authentication", :unauthenticated do
      get admin_provider_fields_connectors_path(provider: "openai")
      expect(response).to redirect_to(new_session_path)
    end
  end
end
