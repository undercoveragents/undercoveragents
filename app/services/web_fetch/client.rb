# frozen_string_literal: true

module WebFetch
  class Client
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

      requested_urls.map do |raw_url|
        uri = WebSearch::Safety.validate_public_url!(raw_url)
        response = @http_client.fetch_text(
          uri,
          max_bytes: MAX_PAGE_BYTES,
          allowed_content_types: ALLOWED_PAGE_CONTENT_TYPES,
        )
        PageExtractor.call(response, focus:)
      end
    rescue WebSearch::Error => e
      raise Error, e.message
    end
  end
end
