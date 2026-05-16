# frozen_string_literal: true

# Connection tester for MCP Server connectors.
class McpServerConnectionTester < BaseConnectionTester
  DEFAULT_TIMEOUT = 15_000

  def call
    transport_type = @params[:transport_type] || "stdio"
    client_config = build_client_config(transport_type)
    test_connection(client_config)
  rescue RubyLLM::MCP::Errors::TransportError => e
    failure("Transport error: #{sanitize_error(e.message)}")
  rescue RubyLLM::MCP::Errors::TimeoutError => e
    failure("Connection timed out: #{sanitize_error(e.message)}")
  rescue StandardError => e
    failure(sanitize_error(e.message))
  end

  private

  def build_client_config(transport_type)
    {
      name: "connection-test-#{SecureRandom.hex(4)}",
      transport_type: transport_type_symbol(transport_type),
      request_timeout: (@params[:request_timeout] || DEFAULT_TIMEOUT).to_i,
      config: build_transport_config(transport_type),
    }
  end

  def transport_type_symbol(transport_type)
    case transport_type
    when "stdio" then :stdio
    when "sse" then :sse
    when "streamable_http" then :streamable
    else transport_type.to_sym
    end
  end

  def build_transport_config(transport_type)
    case transport_type
    when "stdio" then build_stdio_config
    when "sse", "streamable_http" then build_http_config
    else {}
    end
  end

  def build_stdio_config
    config = { command: @params[:command].to_s }
    config[:args] = parse_args(@params[:args]) if @params[:args].present?
    config[:env] = parse_hash(@params[:env_vars]) if @params[:env_vars].present?
    config
  end

  def build_http_config
    config = { url: @params[:url].to_s }
    config[:headers] = parse_hash(@params[:headers]) if @params[:headers].present?
    config[:version] = @params[:http_version].to_sym if @params[:http_version].present?
    config[:oauth] = build_oauth_config if @params[:oauth_enabled].to_s.match?(/\A(true|1)\z/i)
    config
  end

  def build_oauth_config
    {
      client_id: @params[:oauth_client_id],
      client_secret: @params[:oauth_client_secret],
      issuer: @params[:oauth_issuer],
      scope: @params[:oauth_scope],
      redirect_uri: @params[:oauth_redirect_uri],
      grant_type: @params[:oauth_grant_type]&.to_sym,
    }.compact
  end

  def test_connection(client_config)
    client = RubyLLM::MCP.client(**client_config)

    tools = client.tools
    tool_names = tools.map(&:name)

    details = {
      server_name: client_config[:name],
      transport: client_config[:transport_type].to_s,
      tools_count: tools.size,
      tool_names: tool_names.first(20),
    }

    success("Connected successfully — #{tools.size} tool(s) available", details)
  ensure
    stop_client(client)
  end

  def stop_client(client)
    client&.stop
  rescue StandardError
    nil
  end

  def parse_args(args)
    return args if args.is_a?(Array)
    return JSON.parse(args) if args.is_a?(String) && args.start_with?("[")

    args.to_s.split("\n").map(&:strip).compact_blank
  end

  def parse_hash(hash)
    return hash if hash.is_a?(Hash)
    return JSON.parse(hash) if hash.is_a?(String)

    {}
  rescue JSON::ParserError
    {}
  end
end
