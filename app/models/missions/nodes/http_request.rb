# frozen_string_literal: true

module Missions
  module Nodes
    # Node: HTTP Request — makes external HTTP API calls.
    # Supports authentication, query params, multiple body modes, transport
    # controls, and retry behavior.
    # Binary responses (images, audio, PDFs, etc.) are stored as Active Storage
    # attachments on the MissionRun; only file metadata is kept in variables.
    class HttpRequest
      include MissionNodePlugin
      include Missions::BinaryResponseStorage
      include HttpRequestAuthorization
      include HttpRequestPayload
      include HttpRequestTransport

      FIELD_CONTRACT_ATTRIBUTES = [
        { key: "url", kind: :template, value_type: :string, description: "Request URL", required: true },
        {
          key: "method",
          value_type: :string,
          description: "HTTP method (GET, POST, PUT, PATCH, DELETE)",
          required: true,
        },
        { key: "params", kind: :template, value_type: :hash, description: "Query string params" },
        { key: "headers", kind: :template, value_type: :hash, description: "Request headers" },
        { key: "auth_type", value_type: :string, description: "Authorization strategy" },
        { key: "auth_bearer_token", kind: :template, value_type: :string, description: "Bearer token" },
        { key: "auth_username", kind: :template, value_type: :string, description: "Basic auth username" },
        { key: "auth_password", kind: :template, value_type: :string, description: "Basic auth password" },
        { key: "auth_api_key_name", value_type: :string, description: "API key field name" },
        { key: "auth_api_key_value", kind: :template, value_type: :string, description: "API key value" },
        { key: "auth_api_key_in", value_type: :string, description: "API key location: header or query" },
        { key: "body_mode", value_type: :string, description: "Request body mode" },
        { key: "body", kind: :template, value_type: :string, description: "Raw or JSON request body" },
        { key: "body_content_type", value_type: :string, description: "Custom content type for raw/binary bodies" },
        {
          key: "form_urlencoded_body",
          kind: :template,
          value_type: :hash,
          description: "application/x-www-form-urlencoded fields",
        },
        {
          key: "multipart_form_data",
          kind: :template,
          value_type: :hash,
          description: "multipart/form-data fields",
        },
        {
          key: "binary_source",
          kind: :template,
          value_type: :string,
          description: "Template reference to an upstream file variable",
        },
        { key: "verify_ssl", value_type: :boolean, description: "Whether SSL certificates are verified" },
        { key: "connect_timeout", value_type: :number, description: "Connection timeout in seconds" },
        { key: "read_timeout", value_type: :number, description: "Read timeout in seconds" },
        { key: "write_timeout", value_type: :number, description: "Write timeout in seconds" },
        { key: "retry_enabled", value_type: :boolean, description: "Whether retry logic is enabled" },
        { key: "max_retries", value_type: :number, description: "Maximum retry attempts" },
        { key: "retry_interval_ms", value_type: :number, description: "Retry delay in milliseconds" },
      ].freeze

      class << self
        include HttpRequestInstructions

        def node_type = "http_request"
        def node_label = "HTTP Request"
        def node_icon = "fa-solid fa-globe"
        def node_color = "#0284c7"
        def node_category = :node
        def node_description = "Makes an HTTP request to an external API"

        def field_contracts
          FIELD_CONTRACT_ATTRIBUTES.map { |attributes| field_contract(**attributes) }
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "status", type: :number, description: "HTTP status code" },
              { name: "body", type: :any, description: "Response body (text) or file metadata (binary)" },
              { name: "headers", type: :hash, description: "Response headers" },
            ],
          )
        end

        def default_output_ports = [{ key: "success", label: "Success (2xx)" }, { key: "error", label: "Error" }]

        def mutually_exclusive_output_ports? = true
      end

      register_node!

      RequestPayload = Data.define(:body, :body_stream, :content_length, :tempfiles)

      ALLOWED_METHODS = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"].freeze
      ALLOWED_AUTH_TYPES = ["none", "bearer", "basic", "api_key"].freeze
      BODY_MODES = ["none", "json", "raw", "form_urlencoded", "multipart", "binary"].freeze
      BODY_METHODS = ["POST", "PUT", "PATCH", "DELETE"].freeze
      RETRYABLE_STATUS_CODES = [408, 425, 429, 500, 502, 503, 504].freeze
      RETRYABLE_ERRORS = [
        Net::OpenTimeout,
        Net::ReadTimeout,
        Timeout::Error,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        EOFError,
        IOError,
        SocketError,
      ].freeze
      REQUEST_TIMEOUT = 30
      MAX_BODY_SIZE = 5_242_880 # 5 MB
      DEFAULT_VERIFY_SSL = true
      DEFAULT_MAX_RETRIES = 3
      DEFAULT_RETRY_INTERVAL_MS = 100

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}

        method = node_data["method"].to_s.upcase
        uri = build_request_uri(context, node_data)

        return invalid_method_error(method) unless ALLOWED_METHODS.include?(method)
        return invalid_url_error(node_data["url"].to_s) unless uri

        headers = resolve_pairs(context, node_data["headers"])
        params = resolve_pairs(context, node_data["params"])
        apply_authorization!(headers, params, context, node_data)
        merge_query_params!(uri, params)
        payload = build_request_payload(method, headers, context, node_data)

        response = perform_request(method, uri, headers, payload, node_data)
        build_result(response, context, uri.to_s)
      rescue Timeout::Error
        NodeResult.new(status: :failure, output: "Request timed out after #{REQUEST_TIMEOUT}s")
      rescue StandardError => e
        NodeResult.new(status: :failure, output: "HTTP request failed: #{e.message}")
      end

      private

      def build_request_uri(context, node_data)
        raw_url = context.interpolate(node_data["url"].to_s).strip
        return nil if raw_url.blank?

        uri = URI.parse(raw_url)
        return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        uri
      rescue URI::InvalidURIError, URI::BadURIError
        nil
      end

      def resolve_pairs(context, config)
        normalize_pairs(config).each_with_object({}) do |(key, raw_value), result|
          next if key.blank?

          value = resolve_value(context, raw_value)
          next if value.nil?

          result[key.to_s] = stringify_value(value)
        end
      end

      def merge_query_params!(uri, params)
        return if params.blank?

        existing = URI.decode_www_form(String(uri.query))
        uri.query = URI.encode_www_form(existing + params.to_a)
      end

      def normalize_pairs(config)
        case config
        when String
          JSON.parse(config)
        when Hash
          config
        else
          {}
        end
      rescue JSON::ParserError
        {}
      end

      def normalize_boolean(value, default)
        return default if value.nil?

        ActiveModel::Type::Boolean.new.cast(value)
      end

      def resolve_value(context, raw_value)
        return raw_value if raw_value.is_a?(Hash) || raw_value.is_a?(Array)

        ref = template_reference(raw_value)
        return context.get_variable(ref) if ref.present?

        context.interpolate(raw_value.to_s)
      end

      def template_reference(raw_value)
        raw_value.to_s.strip[/\A\{\{([\w.]+)\}\}\z/, 1]
      end

      def stringify_value(value)
        return value.to_json if value.is_a?(Hash) || value.is_a?(Array)

        value.to_s
      end

      def set_header_if_missing(headers, key, value)
        return if value.blank?
        return if headers.keys.any? { |existing| existing.to_s.casecmp?(key) }

        headers[key] = value
      end

      def build_result(response, context, url)
        status_code = response.code.to_i
        content_type = (response["content-type"].to_s.split(";", 2).first || "").strip.downcase
        body = build_response_body(response.body.to_s, content_type, context, url)
        headers = response.each_header.to_h.transform_values { |v| to_utf8(v) }
        port = status_code.between?(200, 299) ? "success" : "error"
        NodeResult.new(status: :success, output: body, next_port: port,
                       variables: { "status" => status_code, "body" => body, "headers" => headers },)
      end

      def invalid_method_error(method)
        NodeResult.new(status: :failure, output: "Invalid HTTP method: #{method}")
      end

      def invalid_url_error(url)
        NodeResult.new(status: :failure, output: "Invalid URL: #{url}. Must be http:// or https://")
      end
    end
  end
end
