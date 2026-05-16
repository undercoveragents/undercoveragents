# frozen_string_literal: true

module Connectors
  # Configurator for MCP Server connectors.
  # Stores transport and connection details in the Connector's JSONB configuration column.
  class McpServer
    include UndercoverAgents::PluginSystem::Configurator
    include ConnectorPlugin

    SENSITIVE_FIELDS = [:oauth_client_secret].freeze
    TRANSPORT_TYPES = ["stdio", "sse", "streamable_http"].freeze
    HTTP_VERSIONS = ["http1", "http2"].freeze
    OAUTH_GRANT_TYPES = ["authorization_code", "client_credentials"].freeze
    FORM_PARTIAL_PATH = File.expand_path("../../views", __dir__).freeze

    # ── Attributes ────────────────────────────────────────────────

    attribute :transport_type, :string, default: "stdio"
    attribute :command, :string
    attribute :args, default: -> { [] }
    attribute :env_vars, default: -> { {} }
    attribute :url, :string
    attribute :headers, default: -> { {} }
    attribute :http_version, :string
    attribute :oauth_enabled, :boolean, default: false
    attribute :oauth_client_id, :string
    attribute :oauth_client_secret, :string
    attribute :oauth_grant_type, :string
    attribute :oauth_issuer, :string
    attribute :oauth_scope, :string
    attribute :oauth_redirect_uri, :string
    attribute :request_timeout, :integer, default: 8000

    # ── Validations ───────────────────────────────────────────────

    validates :transport_type, presence: true, inclusion: { in: TRANSPORT_TYPES }
    validates :command, presence: true, if: :stdio?
    validates :url, presence: true, unless: :stdio?
    validates :url, format: { with: URI::DEFAULT_PARSER.make_regexp(["http", "https"]) },
                    allow_blank: true
    validates :http_version, inclusion: { in: HTTP_VERSIONS }, allow_blank: true
    validates :request_timeout, numericality: { greater_than: 0, less_than_or_equal_to: 120_000 }
    validates :oauth_grant_type, inclusion: { in: OAUTH_GRANT_TYPES }, allow_blank: true

    # ── Plugin Protocol ───────────────────────────────────────────

    key "mcp_server"
    label "MCP Server"
    icon "fa-solid fa-server"
    description "Connect to an MCP server via the Model Context Protocol. " \
                "Access local commands, remote APIs, and external tools."
    sensitive_keys SENSITIVE_FIELDS

    def self.permitted_params(params)
      params.expect(mcp_server: [
                      :transport_type, :command, :url, :http_version,
                      :oauth_enabled, :oauth_client_id, :oauth_client_secret,
                      :oauth_issuer, :oauth_scope, :oauth_redirect_uri, :oauth_grant_type,
                      :request_timeout, :args_text, :env_vars_text, :headers_text,
                      { args: [], env_vars: {}, headers: {} },
                    ])
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    def self.param_key = "mcp_server"
    def self.list_resources_kind = "mcp_server_connectors"
    def self.list_resources_title = "MCP Server Connectors"

    # ── Transport Methods ─────────────────────────────────────────

    def oauth_enabled?
      !!oauth_enabled
    end

    def stdio?
      transport_type == "stdio"
    end

    def sse?
      transport_type == "sse"
    end

    def streamable_http?
      transport_type == "streamable_http"
    end

    def http_transport?
      sse? || streamable_http?
    end

    def transport_label
      case transport_type
      when "stdio" then "STDIO (Local Command)"
      when "sse" then "SSE (Server-Sent Events)"
      when "streamable_http" then "Streamable HTTP"
      else transport_type.to_s.titleize
      end
    end

    def display_endpoint
      if stdio?
        cmd_parts = [command]
        cmd_parts += parsed_args if parsed_args.any?
        cmd_parts.join(" ")
      else
        url.to_s
      end
    end

    def parsed_args
      return [] if args.blank?
      return args if args.is_a?(Array)

      args.to_s.split("\n").map(&:strip).compact_blank
    end

    def parsed_env_vars
      return {} if env_vars.blank?
      return env_vars if env_vars.is_a?(Hash)

      {}
    end

    def parsed_headers
      return {} if headers.blank?
      return headers if headers.is_a?(Hash)

      {}
    end

    def build_client_config
      {
        name: _connector_record&.name&.parameterize || "mcp-server",
        transport_type: transport_type_symbol,
        request_timeout:,
        config: build_transport_config,
      }
    end

    # ── Connection Testing ────────────────────────────────────────

    def connection_test_params
      {
        transport_type:, command:, url:, http_version:, request_timeout:,
        args: parsed_args, env_vars: parsed_env_vars, headers: parsed_headers,
        oauth_enabled: oauth_enabled?, oauth_client_id:, oauth_client_secret:,
        oauth_issuer:, oauth_scope:, oauth_redirect_uri:, oauth_grant_type:,
      }.compact_blank
    end

    # ── Virtual text-field attributes (form ↔ model conversion) ──

    def args_text=(value)
      self.args = value.present? ? value.to_s.split("\n").map(&:strip).compact_blank : []
    end

    def args_text
      args.is_a?(Array) ? args.join("\n") : ""
    end

    def env_vars_text=(value)
      self.env_vars = value.present? ? parse_key_value_text(value) : {}
    end

    def env_vars_text
      return "" unless env_vars.is_a?(Hash)

      env_vars.map { |k, v| "#{k}=#{v}" }.join("\n")
    end

    def headers_text=(value)
      self.headers = value.present? ? parse_key_value_text(value) : {}
    end

    def headers_text
      return "" unless headers.is_a?(Hash)

      headers.map { |k, v| "#{k}=#{v}" }.join("\n")
    end

    def summary
      "#{transport_label} — #{display_endpoint}"
    end

    # ── View Paths ────────────────────────────────────────────────

    def form_partial_path
      FORM_PARTIAL_PATH
    end

    def show_partial_path
      FORM_PARTIAL_PATH
    end

    # ── Serialization ─────────────────────────────────────────────

    def to_configuration
      attrs = super
      attrs.delete("oauth_client_secret") if attrs["oauth_client_secret"].blank?
      attrs
    end

    private

    def transport_type_symbol
      case transport_type
      when "stdio" then :stdio
      when "sse" then :sse
      when "streamable_http" then :streamable
      else transport_type.to_sym
      end
    end

    def build_transport_config
      case transport_type
      when "stdio" then build_stdio_config
      when "sse", "streamable_http" then build_http_config
      end
    end

    def build_stdio_config
      config = { command: }
      config[:args] = parsed_args if parsed_args.any?
      config[:env] = parsed_env_vars if parsed_env_vars.any?
      config
    end

    def build_http_config
      config = { url: }
      config[:headers] = parsed_headers if parsed_headers.any?
      config[:version] = http_version.to_sym if http_version.present?
      config[:oauth] = build_oauth_config if oauth_enabled?
      config
    end

    def build_oauth_config
      {
        client_id: oauth_client_id,
        client_secret: oauth_client_secret,
        issuer: oauth_issuer,
        scope: oauth_scope,
        redirect_uri: oauth_redirect_uri,
        grant_type: oauth_grant_type&.to_sym,
      }.compact
    end

    def parse_key_value_text(text)
      text.to_s.split("\n").each_with_object({}) do |line, result|
        key, value = line.split("=", 2).map(&:strip)
        result[key] = value if key.present? && value.present?
      end
    end
  end
end
