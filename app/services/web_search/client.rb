# frozen_string_literal: true

require "cgi"
require "net/http"
require "uri"

module WebSearch
  class Client
    class Error < StandardError; end

    SearchResult = Data.define(:title, :url, :display_url, :snippet)
    PageResult = Data.define(:url, :title, :description, :snippets, :links, :content_type, :truncated)
    RelatedLink = Data.define(:text, :url)
    FetchResult = Data.define(:uri, :body, :content_type, :truncated)

    SEARCH_HOST = "html.duckduckgo.com"
    SEARCH_PATH = "/html/"
    USER_AGENT = "UndercoverAgentsSafeWebSearch/1.0"
    MAX_RESULTS = 8
    MAX_PAGE = 5
    MAX_URLS_PER_READ = 3
    SEARCH_RESULT_OFFSET = 10
    MAX_SEARCH_BYTES = 180_000
    MAX_PAGE_BYTES = 220_000
    REDIRECT_LIMIT = 3
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 8
    ALLOWED_SEARCH_CONTENT_TYPES = ["text/html", "application/xhtml+xml"].freeze
    ALLOWED_PAGE_CONTENT_TYPES = ["text/html", "application/xhtml+xml", "text/plain"].freeze

    def search(query:, page: 1, max_results: 5)
      normalized_query = query.to_s.strip
      raise Error, "A search query is required." if normalized_query.blank?

      current_page = normalize_page(page)
      limit = normalize_result_limit(max_results)
      response = fetch_text(
        search_uri(query: normalized_query, page: current_page),
        max_bytes: MAX_SEARCH_BYTES,
        allowed_content_types: ALLOWED_SEARCH_CONTENT_TYPES,
      )

      parse_search_results(response.body, max_results: limit)
    end

    def read(urls:, focus: nil)
      requested_urls = Array(urls).flatten.compact_blank.map(&:to_s).uniq
      raise Error, "Provide at least one URL to read." if requested_urls.empty?
      raise Error, "Read at most #{MAX_URLS_PER_READ} URLs per call." if requested_urls.size > MAX_URLS_PER_READ

      requested_urls.map do |raw_url|
        uri = Safety.validate_public_url!(raw_url)
        response = fetch_text(uri, max_bytes: MAX_PAGE_BYTES, allowed_content_types: ALLOWED_PAGE_CONTENT_TYPES)
        PageExtractor.call(response, focus:)
      end
    end

    private

    def normalize_page(page)
      numeric = Integer(page, exception: false) || 1
      numeric.clamp(1, MAX_PAGE)
    end

    def normalize_result_limit(max_results)
      numeric = Integer(max_results, exception: false) || 5
      numeric.clamp(1, MAX_RESULTS)
    end

    def search_uri(query:, page:)
      URI::HTTPS.build(
        host: SEARCH_HOST,
        path: SEARCH_PATH,
        query: URI.encode_www_form(q: query, s: (page - 1) * SEARCH_RESULT_OFFSET),
      )
    end

    def fetch_text(uri_or_url, max_bytes:, allowed_content_types:, redirects_remaining: REDIRECT_LIMIT)
      uri = uri_or_url.is_a?(URI::Generic) ? uri_or_url : Safety.validate_public_url!(uri_or_url)
      payload = perform_request(uri, max_bytes:, allowed_content_types:)

      finalize_response(
        uri:,
        payload:,
        request_options: { max_bytes:, allowed_content_types: },
        redirects_remaining:,
      )
    rescue Net::OpenTimeout, Net::ReadTimeout, IOError, OpenSSL::SSL::SSLError, SocketError => e
      raise Error, "Network request failed: #{e.message}"
    end

    def http_client_for(uri)
      Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http.write_timeout = OPEN_TIMEOUT if http.respond_to?(:write_timeout=)
      end
    end

    def request_for(uri, max_bytes:, allowed_content_types:)
      Net::HTTP::Get.new(uri.request_uri).tap do |request|
        request["User-Agent"] = USER_AGENT
        request["Accept"] = accept_header_for(allowed_content_types)
        request["Range"] = "bytes=0-#{max_bytes - 1}"
      end
    end

    def accept_header_for(allowed_content_types)
      if allowed_content_types == ALLOWED_PAGE_CONTENT_TYPES
        "text/html,application/xhtml+xml,text/plain;q=0.9"
      else
        "text/html,application/xhtml+xml"
      end
    end

    def perform_request(uri, max_bytes:, allowed_content_types:)
      payload = { body: +"", truncated: false, response: nil }

      http_client_for(uri).request(request_for(uri, max_bytes:, allowed_content_types:)) do |http_response|
        payload[:response] = http_response
        next if redirect_response?(http_response)

        ensure_supported_content_type!(http_response, allowed_content_types)
        read_capped_body(http_response, payload[:body], max_bytes:, payload:)
      end

      payload
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

      FetchResult.new(
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

    def parse_search_results(html, max_results:)
      document = Nokogiri::HTML5(html)
      search_result_nodes(document).filter_map do |node|
        link = node.at_css("a.result__a, a.result-link")
        next unless link

        resolved_url = unwrap_duckduckgo_url(link["href"])
        next unless resolved_url
        next unless public_result_url?(resolved_url)

        SearchResult.new(
          title: normalize_text(link.text),
          url: resolved_url,
          display_url: normalize_text(node.at_css(".result__url, .link-text")&.text),
          snippet: normalize_text(node.at_css(".result__snippet, .result-snippet")&.text),
        )
      end.first(max_results)
    end

    def search_result_nodes(document)
      nodes = document.css(".result")
      return nodes if nodes.any?

      document.css("a.result-link").filter_map { |link| link.ancestors("tr").first || link.parent }
    end

    def unwrap_duckduckgo_url(raw_href)
      href = raw_href.to_s
      return if href.blank?

      uri = URI.parse(href.start_with?("//") ? "https:#{href}" : href)
      return uri.to_s if uri.host.present? && uri.host != "duckduckgo.com"

      target = duckduckgo_redirect_target(uri)
      target.present? ? CGI.unescape(target) : nil
    rescue URI::InvalidURIError
      nil
    end

    def duckduckgo_redirect_target(uri)
      URI.decode_www_form(uri.query.to_s).to_h["uddg"]
    rescue ArgumentError
      nil
    end

    def public_result_url?(url)
      Safety.validate_public_url!(url)
      true
    rescue Safety::Error
      false
    end

    def normalize_text(text)
      text.to_s.gsub(/\s+/, " ").strip
    end
  end
end
