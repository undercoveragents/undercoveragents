# frozen_string_literal: true

# == Schema Information
#
# Table name: connectors
# Database name: primary
#
#  id             :bigint           not null, primary key
#  configuration  :jsonb            not null
#  connector_type :string           not null
#  description    :text
#  enabled        :boolean          default(FALSE), not null
#  name           :string           not null
#  slug           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_connectors_on_connector_type           (connector_type)
#  index_connectors_on_enabled                  (enabled)
#  index_connectors_on_name                     (name) UNIQUE
#  index_connectors_on_slug                     (slug) UNIQUE
#  index_connectors_on_telegram_webhook_secret  (((configuration ->> 'webhook_secret'::text))) UNIQUE WHERE (((connector_type)::text = 'telegram'::text) AND ((configuration ->> 'webhook_secret'::text) IS NOT NULL))
#
require "rails_helper"

RSpec.describe Connectors::McpServer do
  subject(:mcp_server) { build(:connectors_mcp_server) }

  describe "list_resources metadata" do
    it "declares the connector kind" do
      expect(described_class.list_resources_kind).to eq("mcp_server_connectors")
      expect(described_class.list_resources_title).to eq("MCP Server Connectors")
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:transport_type) }
    it { is_expected.to validate_inclusion_of(:transport_type).in_array(described_class::TRANSPORT_TYPES) }

    it "rejects request_timeout outside valid range" do
      mcp_server.request_timeout = 0
      expect(mcp_server).not_to be_valid
      expect(mcp_server.errors[:request_timeout]).to be_present
    end

    describe "STDIO transport" do
      subject(:server) { build(:connectors_mcp_server, :stdio, command: nil) }

      it "requires command" do
        expect(server).not_to be_valid
        expect(server.errors[:command]).to include("can't be blank")
      end

      context "with a valid command" do
        subject(:server) { build(:connectors_mcp_server, :stdio) }

        it "is valid" do
          expect(server).to be_valid
        end
      end
    end

    describe "SSE transport" do
      subject(:server) { build(:connectors_mcp_server, :sse, url: nil) }

      it "requires url" do
        expect(server).not_to be_valid
        expect(server.errors[:url]).to include("can't be blank")
      end

      context "with a valid url" do
        subject(:server) { build(:connectors_mcp_server, :sse) }

        it "is valid" do
          expect(server).to be_valid
        end
      end

      context "with an invalid url" do
        subject(:server) { build(:connectors_mcp_server, :sse, url: "not-a-url") }

        it "is invalid" do
          expect(server).not_to be_valid
          expect(server.errors[:url]).to include("is invalid")
        end
      end
    end

    describe "Streamable HTTP transport" do
      subject(:server) { build(:connectors_mcp_server, :streamable_http, url: nil) }

      it "requires url" do
        expect(server).not_to be_valid
        expect(server.errors[:url]).to include("can't be blank")
      end

      context "with a valid url" do
        subject(:server) { build(:connectors_mcp_server, :streamable_http) }

        it "is valid" do
          expect(server).to be_valid
        end
      end
    end

    describe "http_version validation" do
      it "allows blank" do
        server = build(:connectors_mcp_server, :sse, http_version: nil)
        expect(server).to be_valid
      end

      it "allows http1" do
        server = build(:connectors_mcp_server, :sse, http_version: "http1")
        expect(server).to be_valid
      end

      it "allows http2" do
        server = build(:connectors_mcp_server, :sse, http_version: "http2")
        expect(server).to be_valid
      end

      it "rejects invalid values" do
        server = build(:connectors_mcp_server, :sse, http_version: "http3")
        expect(server).not_to be_valid
      end
    end

    describe "oauth_grant_type validation" do
      it "allows blank" do
        server = build(:connectors_mcp_server, :sse, oauth_grant_type: nil)
        expect(server).to be_valid
      end

      it "allows authorization_code" do
        server = build(:connectors_mcp_server, :sse, oauth_grant_type: "authorization_code")
        expect(server).to be_valid
      end

      it "allows client_credentials" do
        server = build(:connectors_mcp_server, :sse, oauth_grant_type: "client_credentials")
        expect(server).to be_valid
      end

      it "rejects invalid values" do
        server = build(:connectors_mcp_server, :sse, oauth_grant_type: "implicit")
        expect(server).not_to be_valid
      end
    end
  end

  describe "transport type predicates" do
    it "identifies stdio transport" do
      server = build(:connectors_mcp_server, :stdio)
      expect(server).to be_stdio
      expect(server).not_to be_sse
      expect(server).not_to be_streamable_http
      expect(server).not_to be_http_transport
    end

    it "identifies sse transport" do
      server = build(:connectors_mcp_server, :sse)
      expect(server).to be_sse
      expect(server).not_to be_stdio
      expect(server).not_to be_streamable_http
      expect(server).to be_http_transport
    end

    it "identifies streamable_http transport" do
      server = build(:connectors_mcp_server, :streamable_http)
      expect(server).to be_streamable_http
      expect(server).not_to be_stdio
      expect(server).not_to be_sse
      expect(server).to be_http_transport
    end
  end

  describe "#transport_label" do
    it "returns label for stdio" do
      expect(build(:connectors_mcp_server, :stdio).transport_label).to eq("STDIO (Local Command)")
    end

    it "returns label for sse" do
      expect(build(:connectors_mcp_server, :sse).transport_label).to eq("SSE (Server-Sent Events)")
    end

    it "returns label for streamable_http" do
      expect(build(:connectors_mcp_server, :streamable_http).transport_label).to eq("Streamable HTTP")
    end

    it "returns titleized label for unknown transport" do
      server = build(:connectors_mcp_server, :stdio)
      allow(server.configurator).to receive(:transport_type).and_return("custom_ws")
      expect(server.transport_label).to eq("Custom Ws")
    end
  end

  describe "#display_endpoint" do
    it "shows command with args for stdio" do
      server = build(:connectors_mcp_server, :stdio)
      expect(server.display_endpoint).to eq("npx -y @modelcontextprotocol/server-filesystem /tmp")
    end

    it "shows just command when no args for stdio" do
      server = build(:connectors_mcp_server, :stdio, args: [])
      expect(server.display_endpoint).to eq("npx")
    end

    it "shows url for sse" do
      server = build(:connectors_mcp_server, :sse)
      expect(server.display_endpoint).to eq("https://mcp.example.com/sse")
    end

    it "shows url for streamable_http" do
      server = build(:connectors_mcp_server, :streamable_http)
      expect(server.display_endpoint).to eq("https://mcp.example.com/mcp")
    end
  end

  describe "#parsed_args" do
    it "returns array from jsonb" do
      server = build(:connectors_mcp_server, args: ["-y", "server-fs"])
      expect(server.parsed_args).to eq(["-y", "server-fs"])
    end

    it "returns empty array when blank" do
      server = build(:connectors_mcp_server, args: [])
      expect(server.parsed_args).to eq([])
    end

    it "returns empty array when nil" do
      server = build(:connectors_mcp_server, args: nil)
      expect(server.parsed_args).to eq([])
    end

    it "parses newline-separated string" do
      server = build(:connectors_mcp_server, args: "-y\n@mcp/server-fs\n/tmp")
      expect(server.parsed_args).to eq(["-y", "@mcp/server-fs", "/tmp"])
    end
  end

  describe "#parsed_env_vars" do
    it "returns hash from jsonb" do
      server = build(:connectors_mcp_server, env_vars: { "KEY" => "value" })
      expect(server.parsed_env_vars).to eq({ "KEY" => "value" })
    end

    it "returns empty hash when blank" do
      server = build(:connectors_mcp_server, env_vars: {})
      expect(server.parsed_env_vars).to eq({})
    end

    it "returns empty hash when nil" do
      server = build(:connectors_mcp_server, env_vars: nil)
      expect(server.parsed_env_vars).to eq({})
    end

    it "returns empty hash for non-hash values" do
      server = build(:connectors_mcp_server, env_vars: "invalid")
      expect(server.parsed_env_vars).to eq({})
    end

    it "returns empty hash for raw non-hash configuration payload" do
      server = build(:connectors_mcp_server)
      allow(server).to receive(:env_vars).and_return("invalid")
      expect(server.parsed_env_vars).to eq({})
    end
  end

  describe "#parsed_headers" do
    it "returns hash from jsonb" do
      server = build(:connectors_mcp_server, :sse, headers: { "Authorization" => "Bearer abc" })
      expect(server.parsed_headers).to eq({ "Authorization" => "Bearer abc" })
    end

    it "returns empty hash when blank" do
      server = build(:connectors_mcp_server, :sse, headers: {})
      expect(server.parsed_headers).to eq({})
    end

    it "returns empty hash when nil" do
      server = build(:connectors_mcp_server, :sse, headers: nil)
      expect(server.parsed_headers).to eq({})
    end

    it "returns empty hash for non-hash values" do
      server = build(:connectors_mcp_server, :sse, headers: "invalid")
      expect(server.parsed_headers).to eq({})
    end

    it "returns empty hash for raw non-hash header payload" do
      server = build(:connectors_mcp_server, :sse)
      allow(server).to receive(:headers).and_return("invalid")
      expect(server.parsed_headers).to eq({})
    end
  end

  describe "private transport helpers" do
    it "supports unknown transport symbols" do
      server = build(:connectors_mcp_server, transport_type: "custom")
      expect(server.configurator.send(:transport_type_symbol)).to eq(:custom)
    end

    it "returns nil for unknown transport config builder" do
      server = build(:connectors_mcp_server, transport_type: "custom")
      expect(server.configurator.send(:build_transport_config)).to be_nil
    end
  end

  describe "#build_client_config" do
    context "with STDIO transport" do
      it "builds correct config" do
        server = build(:connectors_mcp_server, :stdio_github)
        config = server.build_client_config

        expect(config[:transport_type]).to eq(:stdio)
        expect(config[:config][:command]).to eq("npx")
        expect(config[:config][:args]).to eq(["-y", "@modelcontextprotocol/server-github"])
        expect(config[:config][:env]).to eq({ "GITHUB_PERSONAL_ACCESS_TOKEN" => "ghp_test123" })
      end

      it "omits args when empty" do
        server = build(:connectors_mcp_server, :stdio, args: [])
        config = server.build_client_config

        expect(config[:config]).not_to have_key(:args)
      end

      it "omits env when empty" do
        server = build(:connectors_mcp_server, :stdio, env_vars: {})
        config = server.build_client_config

        expect(config[:config]).not_to have_key(:env)
      end
    end

    context "with SSE transport" do
      it "builds correct config" do
        server = build(:connectors_mcp_server, :sse_with_headers)
        config = server.build_client_config

        expect(config[:transport_type]).to eq(:sse)
        expect(config[:config][:url]).to eq("https://mcp.example.com/sse")
        expect(config[:config][:headers]).to eq({ "Authorization" => "Bearer test-token" })
      end

      it "omits headers when empty" do
        server = build(:connectors_mcp_server, :sse, headers: {})
        config = server.build_client_config

        expect(config[:config]).not_to have_key(:headers)
      end

      it "omits version when blank" do
        server = build(:connectors_mcp_server, :sse, http_version: nil)
        config = server.build_client_config

        expect(config[:config]).not_to have_key(:version)
      end

      it "omits oauth when not enabled" do
        server = build(:connectors_mcp_server, :sse, oauth_enabled: false)
        config = server.build_client_config

        expect(config[:config]).not_to have_key(:oauth)
      end
    end

    context "with Streamable HTTP transport and OAuth" do
      it "builds correct config with OAuth" do # rubocop:disable RSpec/MultipleExpectations
        server = build(:connectors_mcp_server, :streamable_http, :with_oauth)
        config = server.build_client_config

        expect(config[:transport_type]).to eq(:streamable)
        expect(config[:config][:url]).to eq("https://mcp.example.com/mcp")
        expect(config[:config][:oauth][:client_id]).to eq("my-client-id")
        expect(config[:config][:oauth][:client_secret]).to eq("my-client-secret")
        expect(config[:config][:oauth][:scope]).to eq("mcp:read mcp:write")
        expect(config[:config][:oauth][:grant_type]).to eq(:authorization_code)
      end

      it "omits blank OAuth fields" do
        server = build(:connectors_mcp_server, :streamable_http,
                       oauth_enabled: true,
                       oauth_client_id: "my-client",
                       oauth_client_secret: nil,
                       oauth_issuer: nil,
                       oauth_scope: nil,
                       oauth_redirect_uri: nil,
                       oauth_grant_type: nil,)
        config = server.build_client_config

        expect(config[:config][:oauth]).to eq({ client_id: "my-client" })
      end

      it "includes all OAuth fields when present" do # rubocop:disable RSpec/MultipleExpectations
        server = build(:connectors_mcp_server, :streamable_http,
                       oauth_enabled: true,
                       oauth_client_id: "id",
                       oauth_client_secret: "secret",
                       oauth_issuer: "https://issuer.example.com",
                       oauth_scope: "read write",
                       oauth_redirect_uri: "https://redirect.example.com/callback",
                       oauth_grant_type: "client_credentials",)
        config = server.build_client_config

        oauth = config[:config][:oauth]
        expect(oauth[:client_id]).to eq("id")
        expect(oauth[:client_secret]).to eq("secret")
        expect(oauth[:issuer]).to eq("https://issuer.example.com")
        expect(oauth[:scope]).to eq("read write")
        expect(oauth[:redirect_uri]).to eq("https://redirect.example.com/callback")
        expect(oauth[:grant_type]).to eq(:client_credentials)
      end
    end

    context "with HTTP version" do
      it "includes version in config" do
        server = build(:connectors_mcp_server, :sse, http_version: "http2")
        config = server.build_client_config

        expect(config[:config][:version]).to eq(:http2)
      end
    end

    context "without connector" do
      it "falls back to default name" do
        server = build(:connectors_mcp_server, :stdio, name: nil)
        config = server.build_client_config

        expect(config[:name]).to eq("mcp-server")
      end

      it "falls back to default name when _connector_record is nil" do
        server = described_class.new(transport_type: "stdio", command: "test")
        config = server.build_client_config

        expect(config[:name]).to eq("mcp-server")
      end
    end

    context "with connector name" do
      it "parameterizes the name" do
        server = build(:connectors_mcp_server, :stdio, name: "My Fancy Server")
        config = server.build_client_config

        expect(config[:name]).to eq("my-fancy-server")
      end
    end
  end

  describe "constants" do
    it "defines TRANSPORT_TYPES" do
      expect(described_class::TRANSPORT_TYPES).to eq(["stdio", "sse", "streamable_http"])
    end

    it "defines HTTP_VERSIONS" do
      expect(described_class::HTTP_VERSIONS).to eq(["http1", "http2"])
    end

    it "defines OAUTH_GRANT_TYPES" do
      expect(described_class::OAUTH_GRANT_TYPES).to eq(["authorization_code", "client_credentials"])
    end

    it "defines SENSITIVE_FIELDS" do
      expect(described_class::SENSITIVE_FIELDS).to eq([:oauth_client_secret])
    end
  end

  describe "virtual text-field attributes" do
    subject(:mcp) { build(:connectors_mcp_server) }

    describe "#args_text=" do
      it "splits multiline text into an array" do
        mcp.args_text = "foo\n  bar  \nbaz"
        expect(mcp.args).to eq(["foo", "bar", "baz"])
      end

      it "assigns empty array for blank input" do
        mcp.args_text = ""
        expect(mcp.args).to eq([])
      end
    end

    describe "#args_text" do
      it "joins array args with newlines" do
        mcp.args = ["a", "b"]
        expect(mcp.args_text).to eq("a\nb")
      end

      it "returns empty string for non-array args" do
        mcp.args = "invalid"
        expect(mcp.args_text).to eq("")
      end
    end

    describe "#env_vars_text=" do
      it "parses KEY=VALUE lines into a hash" do
        mcp.env_vars_text = "FOO=bar\nBAZ=qux"
        expect(mcp.env_vars).to eq("FOO" => "bar", "BAZ" => "qux")
      end

      it "assigns empty hash for blank input" do
        mcp.env_vars_text = ""
        expect(mcp.env_vars).to eq({})
      end
    end

    describe "#env_vars_text" do
      it "formats hash as KEY=VALUE lines" do
        mcp.env_vars = { "A" => "1", "B" => "2" }
        expect(mcp.env_vars_text).to eq("A=1\nB=2")
      end

      it "returns empty string for non-hash env_vars" do
        mcp.env_vars = "invalid"
        expect(mcp.env_vars_text).to eq("")
      end
    end

    describe "#headers_text=" do
      it "parses KEY=VALUE lines into a hash" do
        mcp.headers_text = "Auth=Bearer token\nX-Custom=val"
        expect(mcp.headers).to eq("Auth" => "Bearer token", "X-Custom" => "val")
      end

      it "assigns empty hash for blank input" do
        mcp.headers_text = ""
        expect(mcp.headers).to eq({})
      end
    end

    describe "#headers_text" do
      it "formats hash as KEY=VALUE lines" do
        mcp.headers = { "Content-Type" => "json" }
        expect(mcp.headers_text).to eq("Content-Type=json")
      end

      it "returns empty string for non-hash headers" do
        mcp.headers = "invalid"
        expect(mcp.headers_text).to eq("")
      end
    end
  end

  describe ".build_from_params" do
    it "builds an instance from raw ActionController::Parameters" do
      raw = ActionController::Parameters.new(
        mcp_server: { transport_type: "stdio", command: "npx my-server" },
      )
      server = described_class.build_from_params(raw)
      expect(server).to be_a(described_class)
      expect(server.transport_type).to eq("stdio")
    end
  end

  describe "#summary" do
    it "returns a string combining transport label and endpoint" do
      mcp = build(:connectors_mcp_server, transport_type: "stdio",
                                          command: "npx server",)
      expect(mcp.configurator.summary).to be_a(String)
      expect(mcp.configurator.summary).to include("—")
    end
  end

  describe "#oauth_enabled?" do
    it "returns true when oauth_enabled is true" do
      server = build(:connectors_mcp_server, :sse, oauth_enabled: true)
      expect(server.configurator.oauth_enabled?).to be(true)
    end

    it "returns false when oauth_enabled is false" do
      server = build(:connectors_mcp_server, :sse, oauth_enabled: false)
      expect(server.configurator.oauth_enabled?).to be(false)
    end

    it "returns false when oauth_enabled is nil" do
      server = build(:connectors_mcp_server, :sse, oauth_enabled: nil)
      expect(server.configurator.oauth_enabled?).to be(false)
    end
  end

  describe "#connection_test_params" do
    it "returns a hash with all connection parameters" do
      server = build(:connectors_mcp_server, :stdio)
      params = server.configurator.connection_test_params
      expect(params[:transport_type]).to eq("stdio")
      expect(params[:command]).to eq("npx")
      expect(params[:request_timeout]).to be_present
    end

    it "compacts blank values" do
      server = build(:connectors_mcp_server, :stdio, url: nil, http_version: nil,
                                                     oauth_client_id: nil, oauth_client_secret: nil,)
      params = server.configurator.connection_test_params
      expect(params).not_to have_key(:url)
      expect(params).not_to have_key(:http_version)
    end

    it "includes OAuth params when enabled" do
      server = build(:connectors_mcp_server, :sse, :with_oauth)
      params = server.configurator.connection_test_params
      expect(params[:oauth_enabled]).to be(true)
      expect(params[:oauth_client_id]).to be_present
    end
  end

  describe "#to_configuration" do
    it "removes blank oauth_client_secret" do
      server = build(:connectors_mcp_server, :sse, oauth_client_secret: "")
      config = server.configurator.to_configuration
      expect(config).not_to have_key("oauth_client_secret")
    end

    it "keeps non-blank oauth_client_secret" do
      server = build(:connectors_mcp_server, :sse, oauth_client_secret: "secret123")
      config = server.configurator.to_configuration
      expect(config["oauth_client_secret"]).to eq("secret123")
    end
  end

  describe "#form_partial_path and #show_partial_path" do
    it "returns the expected view directory" do
      server = build(:connectors_mcp_server, :stdio)
      path = server.configurator.form_partial_path
      expect(path).to include("views")
      expect(server.configurator.show_partial_path).to eq(path)
    end
  end

  describe "#display_endpoint edge cases" do
    it "returns command without args when parsed_args is empty" do
      server = build(:connectors_mcp_server, :stdio, command: "npx", args: [])
      expect(server.configurator.display_endpoint).to eq("npx")
    end
  end
end
