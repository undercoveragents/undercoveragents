# frozen_string_literal: true

module WebFetch
  class Client
    IDENTITY_ENCODING_HEADERS = { "Accept-Encoding" => "identity" }.freeze
    MAX_URLS_PER_READ = 3
    MAX_PAGE_BYTES = 220_000
    ALLOWED_PAGE_CONTENT_TYPES = ["text/html", "application/xhtml+xml", "text/plain"].freeze

    def initialize(http_client: WebSearch::HttpClient.new)
      @http_client = http_client
    end

    def read(urls:, focus: nil)
      requested_urls = Array(urls).flatten.compact_blank.map(&:to_s).uniq
      raise Error, "Provide at least one URL to read." if requested_urls.empty?
      raise Error, "Read at most #{MAX_URLS_PER_READ} URLs per call." if requested_urls.size > MAX_URLS_PER_READ

      requested_urls.map { |raw_url| read_page(raw_url, focus:) }
    end

    private

    def read_page(raw_url, focus:)
      uri = WebSearch::Safety.validate_public_url!(raw_url)
      response = fetch_page_response(uri)
      PageExtractor.call(response, focus:)
    rescue WebSearch::Error => e
      raise Error, "Failed to fetch #{uri || raw_url}: #{e.message}"
    end

    def fetch_page_response(uri)
      request_page(uri, headers: IDENTITY_ENCODING_HEADERS)
    rescue WebSearch::Error
      request_page_with_fallbacks(uri)
    end

    def request_page_with_fallbacks(uri)
      request_page(uri)
    rescue WebSearch::Error => e
      retry_without_range(uri, error: e)
    end

    def request_page(uri, headers: {}, range_request: true)
      @http_client.fetch_text(
        uri,
        max_bytes: MAX_PAGE_BYTES,
        allowed_content_types: ALLOWED_PAGE_CONTENT_TYPES,
        headers:,
        range_request:,
      )
    end

    def retry_without_range(uri, error:)
      raise error unless network_request_failed?(error)

      request_page(uri, range_request: false)
    rescue StandardError
      raise error
    end

    def network_request_failed?(error)
      error.message.start_with?("Network request failed:")
    end
  end
end
