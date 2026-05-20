# frozen_string_literal: true

require "cgi"
require "nokogiri"
require "uri"

module WebSearch
  module Clients
    class DuckDuckGoClient
      SEARCH_HOST = "html.duckduckgo.com"
      SEARCH_PATH = "/html/"
      SEARCH_RESULT_OFFSET = 10
      MAX_SEARCH_BYTES = 180_000
      ALLOWED_CONTENT_TYPES = ["text/html", "application/xhtml+xml"].freeze

      def initialize(http_client: WebSearch::HttpClient.new)
        @http_client = http_client
      end

      def search(query:, page:, max_results:)
        raise Error, "A search query is required." if query.blank?

        response = @http_client.fetch_text(
          search_uri(query:, page:),
          max_bytes: MAX_SEARCH_BYTES,
          allowed_content_types: ALLOWED_CONTENT_TYPES,
        )
        parse_search_results(response.body, max_results:)
      end

      private

      def search_uri(query:, page:)
        URI::HTTPS.build(
          host: SEARCH_HOST,
          path: SEARCH_PATH,
          query: URI.encode_www_form(q: query, s: (page - 1) * SEARCH_RESULT_OFFSET),
        )
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
        WebSearch::Safety.validate_public_url!(url)
        true
      rescue WebSearch::Safety::Error
        false
      end

      def normalize_text(text)
        text.to_s.gsub(/\s+/, " ").strip
      end
    end
  end
end
