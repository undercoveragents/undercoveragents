# frozen_string_literal: true

require "net/http"
require "uri"

module WebSearch
  class HttpClient
    Response = Data.define(:uri, :body, :content_type, :truncated)

    USER_AGENT = "UndercoverAgentsSafeWebSearch/1.0"
    REDIRECT_LIMIT = 3
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 8

    def fetch_text(uri_or_url, max_bytes:, allowed_content_types:, redirects_remaining: REDIRECT_LIMIT,
                   **request_options)
      uri = uri_or_url.is_a?(URI::Generic) ? uri_or_url : Safety.validate_public_url!(uri_or_url)
      payload = perform_request(
        uri,
        max_bytes:,
        allowed_content_types:,
        headers: request_options.fetch(:headers, {}),
        range_request: request_options.fetch(:range_request, true),
      )

      finalize_response(
        uri:,
        payload:,
        request_options: { max_bytes:, allowed_content_types: }.merge(request_options),
        redirects_remaining:,
      )
    rescue Net::OpenTimeout, Net::ReadTimeout, IOError, OpenSSL::SSL::SSLError, SocketError => e
      raise Error, "Network request failed: #{e.message}"
    end

    private

    def perform_request(uri, max_bytes:, allowed_content_types:, headers:, range_request:)
      payload = { body: +"", truncated: false, response: nil }

      request = request_for(uri, max_bytes:, allowed_content_types:, headers:, range_request:)

      http_client_for(uri).request(request) do |http_response|
        payload[:response] = http_response
        next if redirect_response?(http_response)

        ensure_supported_content_type!(http_response, allowed_content_types)
        read_capped_body(http_response, payload[:body], max_bytes:, payload:)
      end

      payload
    end

    def http_client_for(uri)
      Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http.write_timeout = OPEN_TIMEOUT if http.respond_to?(:write_timeout=)
      end
    end

    def request_for(uri, max_bytes:, allowed_content_types:, headers:, range_request:)
      Net::HTTP::Get.new(uri.request_uri).tap do |request|
        request["User-Agent"] = USER_AGENT
        request["Accept"] = accept_header_for(allowed_content_types)
        request["Range"] = "bytes=0-#{max_bytes - 1}" if range_request
        headers.each { |key, value| request[key] = value }
      end
    end

    def accept_header_for(allowed_content_types)
      types = Array(allowed_content_types).compact_blank
      types.present? ? types.join(",") : "*/*"
    end

    def ensure_supported_content_type!(response, allowed_content_types)
      content_type = normalized_content_type(response)
      return if allowed_content?(content_type, allowed_content_types)

      raise Error, "Unsupported content type: #{content_type.presence || "unknown"}."
    end

    def read_capped_body(response, body, max_bytes:, payload:)
      catch(:stop_reading) do
        response.read_body do |chunk|
          remaining = max_bytes - body.bytesize
          if remaining <= 0
            payload[:truncated] = true
            throw :stop_reading
          end

          piece = chunk.byteslice(0, remaining)
          body << piece
          next unless piece.bytesize < chunk.bytesize

          payload[:truncated] = true
          throw :stop_reading
        end
      end
    end

    def finalize_response(uri:, payload:, request_options:, redirects_remaining:)
      response = payload.fetch(:response)
      raise Error, "No HTTP response was received." unless response

      return follow_redirect(response, uri, request_options, redirects_remaining) if redirect_response?(response)
      raise Error, "HTTP request failed with status #{response.code}." unless response.is_a?(Net::HTTPSuccess)

      Response.new(
        uri: uri.to_s,
        body: sanitize_text_body(payload[:body]),
        content_type: normalized_content_type(response),
        truncated: payload[:truncated] || content_length_exceeded?(response, request_options[:max_bytes]),
      )
    end

    def follow_redirect(response, uri, request_options, redirects_remaining)
      raise Error, "Too many redirects." if redirects_remaining <= 0

      location = response["location"].to_s
      raise Error, "Redirect response did not include a location." if location.blank?

      next_uri = Safety.validate_public_url!(uri.merge(location).to_s)
      fetch_text(next_uri, redirects_remaining: redirects_remaining - 1, **request_options)
    end

    def content_length_exceeded?(response, max_bytes)
      content_length = Integer(response["content-length"], exception: false)
      content_length.present? && content_length > max_bytes
    end

    def redirect_response?(response)
      response.is_a?(Net::HTTPRedirection)
    end

    def normalized_content_type(response)
      response["content-type"].to_s.split(";", 2).first.to_s.strip.downcase
    end

    def allowed_content?(content_type, allowed_content_types)
      return true if content_type.blank?

      allowed_content_types.include?(content_type)
    end

    def sanitize_text_body(body)
      body.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").delete("\x00")
    end
  end
end
